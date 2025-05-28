const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3ext.h");
    @cInclude("uuid/uuid.h");
    @cDefine("SQLITE_CORE", "1");
    @cDefine("SQLITE_EXTENSION_INIT1", "");
});

/// Store the SQLite API pointer globally
var sqlite3_api: c.sqlite3_api_routines = undefined;

/// SQLite extension initialization
export fn sqlite3_uuidz_init(
    db: ?*c.sqlite3,
    pzErrMsg: [*c][*c]u8,
    pApi: [*c]c.sqlite3_api_routines,
) callconv(.C) c_int {
    _ = pzErrMsg;

    // Initialize the SQLite API
    sqlite3_api = pApi.*;

    // Register the hello_world function
    return sqlite3_api.create_function.?(
        db,
        "hello_world",
        0,
        c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC,
        null,
        helloWorldFunc,
        null,
        null,
    );
}

/// Implementation of the hello_world() SQL function
fn helloWorldFunc(
    context: ?*c.sqlite3_context,
    argc: c_int,
    argv: [*c]?*c.sqlite3_value,
) callconv(.C) void {
    _ = argc;
    _ = argv;

    var uuid_buf: c.uuid_t = undefined;

    // Generate a random UUID
    c.uuid_generate(uuid_buf[0..].ptr);

    // Return the UUID as a blob result
    sqlite3_api.result_blob.?(context, &uuid_buf, @sizeOf(c.uuid_t), c.SQLITE_TRANSIENT);
}

test "test sqlite extension compiles" {
    // This is just a compilation test
    std.testing.refAllDeclsRecursive(@This());
}
