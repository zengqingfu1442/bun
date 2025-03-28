const bun = @import("root").bun;
const JSC = bun.JSC;
const std = @import("std");
const JSGlobalObject = JSC.JSGlobalObject;
const JSValue = JSC.JSValue;
const ErrorableString = JSC.ErrorableString;

// https://github.com/nodejs/node/blob/40ef9d541ed79470977f90eb445c291b95ab75a0/lib/internal/modules/cjs/loader.js#L666
pub export fn NodeModuleModule__findPath(
    global: *JSGlobalObject,
    request_bun_str: bun.String,
    paths_maybe: ?*JSC.JSArray,
) JSValue {
    var stack_buf = std.heap.stackFallback(8192, bun.default_allocator);
    const alloc = stack_buf.get();

    const request_slice = request_bun_str.toUTF8(alloc);
    defer request_slice.deinit();
    const request = request_slice.slice();

    const absolute_request = std.fs.path.isAbsolute(request);
    if (!absolute_request and paths_maybe == null) {
        return .false;
    }

    // for each path
    const found = if (paths_maybe) |paths| found: {
        var iter = paths.iterator(global);
        while (iter.next()) |path| {
            const cur_path = bun.String.fromJS(path, global) catch |err| switch (err) {
                error.JSError => return .zero,
                error.OutOfMemory => return global.throwOutOfMemoryValue(),
            };
            defer cur_path.deref();

            if (findPathInner(request_bun_str, cur_path, global)) |found| {
                break :found found;
            }
        }

        break :found null;
    } else findPathInner(request_bun_str, bun.String.static(""), global);

    if (found) |str| {
        return str.toJS(global);
    }

    return .false;
}

fn findPathInner(
    request: bun.String,
    cur_path: bun.String,
    global: *JSGlobalObject,
) ?bun.String {
    var errorable: ErrorableString = undefined;
    JSC.VirtualMachine.resolveMaybeNeedsTrailingSlash(
        &errorable,
        global,
        request,
        cur_path,
        null,
        false,
        true,
        true,
    ) catch |err| switch (err) {
        error.JSError => {
            global.clearException();
            return null;
        },
        else => return null,
    };
    return errorable.unwrap() catch null;
}

pub fn _stat(path: []const u8) i32 {
    const exists = bun.sys.existsAtType(.cwd(), path).unwrap() catch
        return -1; // Returns a negative integer for any other kind of strings.
    return switch (exists) {
        .file => 0, // Returns 0 for files.
        .directory => 1, // Returns 1 for directories.
    };
}
