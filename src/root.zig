const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3ext.h");
    @cInclude("uuid/uuid.h");
    @cDefine("SQLITE_CORE", "1");
    @cDefine("SQLITE_EXTENSION_INIT1", "");
});

var sqlite3_api: c.sqlite3_api_routines = undefined;

const UUID_BYTE_SIZE = 16;
const UUID_STRING_LENGTH = 36;
const UUID_STRING_BUFFER_SIZE = 37; // Including null terminator
const UUID_STRING_LENGTH_NO_HYPHENS = 32;
const UUID_HYPHEN_POSITIONS = [_]usize{ 8, 13, 18, 23 };

export fn sqlite3_uuidz_init(
    db: ?*c.sqlite3,
    pzErrMsg: [*c][*c]u8,
    pApi: [*c]c.sqlite3_api_routines,
) callconv(.C) c_int {
    _ = pzErrMsg;

    if (db == null or pApi == null) {
        return c.SQLITE_ERROR;
    }

    sqlite3_api = pApi.*;

    var result: c_int = 0;

    result = sqlite3_api.create_function.?(db, "uuid_v1", 0, c.SQLITE_UTF8, null, uuidV1Func, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_v3", 2, c.SQLITE_UTF8, null, uuidV3Func, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_v4", 0, c.SQLITE_UTF8, null, uuidV4Func, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_v5", 2, c.SQLITE_UTF8, null, uuidV5Func, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_v6", 0, c.SQLITE_UTF8, null, uuidV6Func, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_v7", 0, c.SQLITE_UTF8, null, uuidV7Func, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_format", 1, c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC, null, uuidToTextFunc, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_parse", 1, c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC, null, uuidFromTextFunc, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_version", 1, c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC, null, uuidVersionFunc, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_variant", 1, c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC, null, uuidVariantFunc, null, null);
    if (result != c.SQLITE_OK) return result;

    result = sqlite3_api.create_function.?(db, "uuid_timestamp", 1, c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC, null, uuidTimestampFunc, null, null);
    if (result != c.SQLITE_OK) return result;

    return c.SQLITE_OK;
}

fn uuidV1Func(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    _ = argc;
    _ = argv;

    var uuid_buf: c.uuid_t = undefined;
    c.uuid_generate_time(uuid_buf[0..].ptr);
    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

fn uuidV3Func(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    if (argc != 2) {
        sqlite3_api.result_error.?(context, "uuid_v3: requires exactly 2 arguments (namespace UUID blob, name text)", -1);
        return;
    }

    const ns_blob = sqlite3_api.value_blob.?(argv[0]);
    if (ns_blob == null) {
        sqlite3_api.result_error.?(context, "uuid_v3: namespace UUID blob cannot be null", -1);
        return;
    }

    const ns_size = sqlite3_api.value_bytes.?(argv[0]);
    if (ns_size != UUID_BYTE_SIZE) {
        sqlite3_api.result_error.?(context, "uuid_v3: namespace must be a 16-byte UUID blob", -1);
        return;
    }

    const name_ptr = sqlite3_api.value_text.?(argv[1]);
    const name_len = sqlite3_api.value_bytes.?(argv[1]);
    if (name_ptr == null) {
        sqlite3_api.result_error.?(context, "uuid_v3: name text cannot be null", -1);
        return;
    }

    var uuid_buf: c.uuid_t = undefined;
    var ns_uuid: c.uuid_t = undefined;

    // Safety: We already verified ns_size == UUID_BYTE_SIZE above
    const ns_bytes = @as([*]const u8, @ptrCast(ns_blob))[0..UUID_BYTE_SIZE];
    @memcpy(ns_uuid[0..], ns_bytes);

    c.uuid_generate_md5(uuid_buf[0..].ptr, ns_uuid[0..].ptr, @as([*c]const u8, @ptrCast(name_ptr)), @as(usize, @intCast(name_len)));
    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

fn uuidV4Func(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    _ = argc;
    _ = argv;

    var uuid_buf: c.uuid_t = undefined;
    c.uuid_generate_random(uuid_buf[0..].ptr);
    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

fn uuidV5Func(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    if (argc != 2) {
        sqlite3_api.result_error.?(context, "uuid_v5: requires exactly 2 arguments (namespace UUID blob, name text)", -1);
        return;
    }

    const ns_blob = sqlite3_api.value_blob.?(argv[0]);
    if (ns_blob == null) {
        sqlite3_api.result_error.?(context, "uuid_v5: namespace UUID blob cannot be null", -1);
        return;
    }

    const ns_size = sqlite3_api.value_bytes.?(argv[0]);
    if (ns_size != UUID_BYTE_SIZE) {
        sqlite3_api.result_error.?(context, "uuid_v5: namespace must be a 16-byte UUID blob", -1);
        return;
    }

    const name_ptr = sqlite3_api.value_text.?(argv[1]);
    const name_len = sqlite3_api.value_bytes.?(argv[1]);
    if (name_ptr == null) {
        sqlite3_api.result_error.?(context, "uuid_v5: name text cannot be null", -1);
        return;
    }

    var uuid_buf: c.uuid_t = undefined;
    var ns_uuid: c.uuid_t = undefined;

    // Safety: We already verified ns_size == UUID_BYTE_SIZE above
    const ns_bytes = @as([*]const u8, @ptrCast(ns_blob))[0..UUID_BYTE_SIZE];
    @memcpy(ns_uuid[0..], ns_bytes);

    c.uuid_generate_sha1(uuid_buf[0..].ptr, ns_uuid[0..].ptr, @as([*c]const u8, @ptrCast(name_ptr)), @as(usize, @intCast(name_len)));
    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

fn uuidV6Func(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    _ = argc;
    _ = argv;

    var uuid_buf: c.uuid_t = undefined;
    c.uuid_generate_time_v6(uuid_buf[0..].ptr);
    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

fn uuidV7Func(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    _ = argc;
    _ = argv;

    var uuid_buf: c.uuid_t = undefined;
    c.uuid_generate_time_v7(uuid_buf[0..].ptr);
    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

fn uuidToTextFunc(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    if (argc != 1) {
        sqlite3_api.result_error.?(context, "uuid_format: requires exactly 1 argument (UUID blob)", -1);
        return;
    }

    const uuid_blob = sqlite3_api.value_blob.?(argv[0]);
    if (uuid_blob == null) {
        sqlite3_api.result_error.?(context, "uuid_format: UUID blob cannot be null", -1);
        return;
    }

    const uuid_size = sqlite3_api.value_bytes.?(argv[0]);
    if (uuid_size != UUID_BYTE_SIZE) {
        sqlite3_api.result_error.?(context, "uuid_format: argument must be a 16-byte UUID blob", -1);
        return;
    }

    var uuid_buf: c.uuid_t = undefined;

    // Safety: We already verified uuid_size == UUID_BYTE_SIZE above
    const uuid_bytes = @as([*]const u8, @ptrCast(uuid_blob))[0..UUID_BYTE_SIZE];
    @memcpy(uuid_buf[0..], uuid_bytes);

    var str_buf: [UUID_STRING_BUFFER_SIZE]u8 = undefined;
    c.uuid_unparse_lower(uuid_buf[0..].ptr, &str_buf);

    if (str_buf[UUID_STRING_LENGTH] != 0) {
        str_buf[UUID_STRING_LENGTH] = 0; // Force null termination
    }

    sqlite3_api.result_text.?(context, &str_buf, UUID_STRING_LENGTH, c.SQLITE_TRANSIENT);
}

fn uuidFromTextFunc(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    if (argc != 1) {
        sqlite3_api.result_error.?(context, "uuid_parse: requires exactly 1 argument (UUID text)", -1);
        return;
    }

    const uuid_str = sqlite3_api.value_text.?(argv[0]);
    if (uuid_str == null) {
        sqlite3_api.result_error.?(context, "uuid_parse: UUID text cannot be null", -1);
        return;
    }

    const uuid_len = sqlite3_api.value_bytes.?(argv[0]);
    if (uuid_len != UUID_STRING_LENGTH and uuid_len != UUID_STRING_LENGTH_NO_HYPHENS) {
        sqlite3_api.result_error.?(context, "uuid_parse: UUID text must be 36 characters (with hyphens) or 32 characters (without hyphens)", -1);
        return;
    }

    var uuid_buf: c.uuid_t = undefined;
    const parse_result = c.uuid_parse(@as([*c]const u8, @ptrCast(uuid_str)), uuid_buf[0..].ptr);

    if (parse_result != 0) {
        sqlite3_api.result_error.?(context, "uuid_parse: invalid UUID text format", -1);
        return;
    }

    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

fn uuidVersionFunc(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    if (argc != 1) {
        sqlite3_api.result_error.?(context, "uuid_version: requires exactly 1 argument (UUID blob)", -1);
        return;
    }

    const uuid_blob = sqlite3_api.value_blob.?(argv[0]);
    if (uuid_blob == null) {
        sqlite3_api.result_error.?(context, "uuid_version: UUID blob cannot be null", -1);
        return;
    }

    const uuid_size = sqlite3_api.value_bytes.?(argv[0]);
    if (uuid_size != UUID_BYTE_SIZE) {
        sqlite3_api.result_error.?(context, "uuid_version: argument must be a 16-byte UUID blob", -1);
        return;
    }

    var uuid_buf: c.uuid_t = undefined;

    // Safety: We already verified uuid_size == UUID_BYTE_SIZE above
    const uuid_bytes = @as([*]const u8, @ptrCast(uuid_blob))[0..UUID_BYTE_SIZE];
    @memcpy(uuid_buf[0..], uuid_bytes);

    const version = c.uuid_type(uuid_buf[0..].ptr);

    // Validate that the version is in a reasonable range (0-8)
    if (version < 0 or version > 8) {
        sqlite3_api.result_error.?(context, "uuid_version: invalid UUID version detected", -1);
        return;
    }

    sqlite3_api.result_int.?(context, version);
}

fn uuidVariantFunc(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    if (argc != 1) {
        sqlite3_api.result_error.?(context, "uuid_variant: requires exactly 1 argument (UUID blob)", -1);
        return;
    }

    const uuid_blob = sqlite3_api.value_blob.?(argv[0]);
    if (uuid_blob == null) {
        sqlite3_api.result_error.?(context, "uuid_variant: UUID blob cannot be null", -1);
        return;
    }

    const uuid_size = sqlite3_api.value_bytes.?(argv[0]);
    if (uuid_size != UUID_BYTE_SIZE) {
        sqlite3_api.result_error.?(context, "uuid_variant: argument must be a 16-byte UUID blob", -1);
        return;
    }

    var uuid_buf: c.uuid_t = undefined;

    // Safety: We already verified uuid_size == UUID_BYTE_SIZE above
    const uuid_bytes = @as([*]const u8, @ptrCast(uuid_blob))[0..UUID_BYTE_SIZE];
    @memcpy(uuid_buf[0..], uuid_bytes);

    const variant = c.uuid_variant(uuid_buf[0..].ptr);

    // Validate that the variant is in a reasonable range
    if (variant < 0 or variant > 3) {
        sqlite3_api.result_error.?(context, "uuid_variant: invalid UUID variant detected", -1);
        return;
    }

    sqlite3_api.result_int.?(context, variant);
}

fn uuidTimestampFunc(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    if (argc != 1) {
        sqlite3_api.result_error.?(context, "uuid_timestamp: requires exactly 1 argument (UUID blob)", -1);
        return;
    }

    const uuid_blob = sqlite3_api.value_blob.?(argv[0]);
    if (uuid_blob == null) {
        sqlite3_api.result_error.?(context, "uuid_timestamp: UUID blob cannot be null", -1);
        return;
    }

    const uuid_size = sqlite3_api.value_bytes.?(argv[0]);
    if (uuid_size != UUID_BYTE_SIZE) {
        sqlite3_api.result_error.?(context, "uuid_timestamp: argument must be a 16-byte UUID blob", -1);
        return;
    }

    var uuid_buf: c.uuid_t = undefined;

    // Safety: We already verified uuid_size == UUID_BYTE_SIZE above
    const uuid_bytes = @as([*]const u8, @ptrCast(uuid_blob))[0..UUID_BYTE_SIZE];
    @memcpy(uuid_buf[0..], uuid_bytes);

    const version = c.uuid_type(uuid_buf[0..].ptr);
    if (version != 1 and version != 6 and version != 7) {
        sqlite3_api.result_error.?(context, "uuid_timestamp: UUID must be time-based (version 1, 6, or 7) to extract timestamp", -1);
        return;
    }

    var tv: c.struct_timeval = undefined;
    _ = c.uuid_time(uuid_buf[0..].ptr, &tv);

    const timestamp = @as(f64, @floatFromInt(tv.tv_sec)) + (@as(f64, @floatFromInt(tv.tv_usec)) / 1000000.0);

    sqlite3_api.result_double.?(context, timestamp);
}

test "test sqlite extension compiles" {
    std.testing.refAllDeclsRecursive(@This());
}
