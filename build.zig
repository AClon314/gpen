const std = @import("std");

const name = "gpen";
const amo_key_url = "https://addons.mozilla.org/en-US/developers/addon/api/key/";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const push_with_adb = b.option(bool, "adb", "Push the built Firefox XPI to /sdcard/Download/ with adb") orelse false;
    const amo_secret_path = "secret.json";
    const secret_seed_path = "scripts/secret.json";
    const amo_secret_exists = fileExists(b, amo_secret_path);
    const amo_secret_configured = amo_secret_exists and amoSecretConfigured(b, amo_secret_path);
    const secret_seed_exists = fileExists(b, secret_seed_path);

    const gpen_mod = b.addModule(name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const static_lib = b.addLibrary(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    b.installArtifact(static_lib);

    const shared_lib = b.addLibrary(.{
        .name = "gpen_core",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/abi/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = name, .module = gpen_mod },
            },
        }),
        .linkage = .dynamic,
    });
    b.installArtifact(shared_lib);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_module = b.addExecutable(.{
        .name = "gpen_wasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/abi/wasm.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = name, .module = gpen_mod },
            },
        }),
    });
    wasm_module.entry = .disabled;
    wasm_module.rdynamic = true;
    b.installArtifact(wasm_module);

    const browser_chrome_dir = b.addInstallDirectory(.{
        .source_dir = b.path("hosts/browser-ext"),
        .install_dir = .prefix,
        .install_subdir = "browser-ext-chrome",
    });
    const browser_firefox_dir = b.addInstallDirectory(.{
        .source_dir = b.path("hosts/browser-ext"),
        .install_dir = .prefix,
        .install_subdir = "browser-ext-firefox",
    });
    const chrome_manifest = b.addInstallFileWithDir(
        b.path("hosts/browser-ext/manifest.chrome.json"),
        .prefix,
        "browser-ext-chrome/manifest.json",
    );
    const firefox_manifest = b.addInstallFileWithDir(
        b.path("hosts/browser-ext/manifest.firefox.json"),
        .prefix,
        "browser-ext-firefox/manifest.json",
    );
    const chrome_wasm = b.addInstallFileWithDir(
        wasm_module.getEmittedBin(),
        .prefix,
        "browser-ext-chrome/gpen_wasm.wasm",
    );
    const firefox_wasm = b.addInstallFileWithDir(
        wasm_module.getEmittedBin(),
        .prefix,
        "browser-ext-firefox/gpen_wasm.wasm",
    );

    const demo_step = b.step("demo", "Build browser extension demo bundles");
    demo_step.dependOn(&browser_chrome_dir.step);
    demo_step.dependOn(&browser_firefox_dir.step);
    demo_step.dependOn(&chrome_manifest.step);
    demo_step.dependOn(&firefox_manifest.step);
    demo_step.dependOn(&chrome_wasm.step);
    demo_step.dependOn(&firefox_wasm.step);

    const firefox_demo_dir = b.getInstallPath(.prefix, "browser-ext-firefox");
    const package_firefox_xpi = b.addSystemCommand(&.{ "/usr/sbin/zip", "-r", "-FS" });
    package_firefox_xpi.step.dependOn(demo_step);
    package_firefox_xpi.setCwd(.{ .cwd_relative = firefox_demo_dir });
    const firefox_xpi_output = package_firefox_xpi.addOutputFileArg("gpen-debug-firefox-unsigned.xpi");
    package_firefox_xpi.addArg(".");
    const install_firefox_xpi = b.addInstallFileWithDir(
        firefox_xpi_output,
        .prefix,
        "gpen-debug-firefox-unsigned.xpi",
    );

    const xpi_firefox_step = b.step(
        "xpi-firefox",
        "Build a Firefox XPI bundle and sign it with AMO when secret.json is configured",
    );
    xpi_firefox_step.dependOn(&install_firefox_xpi.step);

    var package_to_push_step: *std.Build.Step = &install_firefox_xpi.step;
    var package_to_push_path = b.getInstallPath(.prefix, "gpen-debug-firefox-unsigned.xpi");

    if (amo_secret_configured) {
        const sign_firefox_xpi = b.addSystemCommand(&.{"/usr/sbin/node"});
        sign_firefox_xpi.setName("sign Firefox XPI with AMO");
        sign_firefox_xpi.stdio = .inherit;
        sign_firefox_xpi.step.dependOn(&install_firefox_xpi.step);
        sign_firefox_xpi.addFileArg(b.path("scripts/sign_amo_firefox.mjs"));
        sign_firefox_xpi.addArg(b.getInstallPath(.prefix, "gpen-debug-firefox-unsigned.xpi"));
        sign_firefox_xpi.addFileArg(b.path("hosts/browser-ext/manifest.firefox.json"));
        sign_firefox_xpi.addFileArg(b.path(amo_secret_path));
        const signed_firefox_xpi = sign_firefox_xpi.addOutputFileArg("gpen-debug-firefox-signed.xpi");
        const install_signed_firefox_xpi = b.addInstallFileWithDir(
            signed_firefox_xpi,
            .prefix,
            "gpen-debug-firefox-signed.xpi",
        );
        xpi_firefox_step.dependOn(&install_signed_firefox_xpi.step);
        package_to_push_step = &install_signed_firefox_xpi.step;
        package_to_push_path = b.getInstallPath(.prefix, "gpen-debug-firefox-signed.xpi");
    } else if (amo_secret_exists) {
        std.log.warn(
            "AMO signing disabled: {s} exists but does not contain a usable Firefox issuer/secret yet. Fill it with credentials from {s}. Only the unsigned Firefox XPI will be produced this run.",
            .{ amo_secret_path, amo_key_url },
        );
    } else if (secret_seed_exists) {
        const copy_secret_seed = b.addSystemCommand(&.{ "/bin/cp", secret_seed_path, amo_secret_path });
        xpi_firefox_step.dependOn(&copy_secret_seed.step);
        std.log.warn(
            "AMO signing disabled: missing {s}. Copied {s} to the repo root. Fill it with credentials from {s}. Only the unsigned Firefox XPI will be produced this run.",
            .{ amo_secret_path, secret_seed_path, amo_key_url },
        );
    } else {
        std.log.warn(
            "AMO signing disabled: missing {s}, and no seed file was found at {s}. Create JWT credentials at {s}. Only the unsigned Firefox XPI will be produced.",
            .{ amo_secret_path, secret_seed_path, amo_key_url },
        );
    }

    if (push_with_adb) {
        const adb_push = b.addSystemCommand(&.{ "/usr/sbin/adb", "push" });
        adb_push.step.dependOn(package_to_push_step);
        adb_push.addArg(package_to_push_path);
        adb_push.addArg("/sdcard/Download/");
        xpi_firefox_step.dependOn(&adb_push.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = gpen_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const c_api_tests = b.addTest(.{
        .root_module = shared_lib.root_module,
    });
    const run_c_api_tests = b.addRunArtifact(c_api_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_c_api_tests.step);
}

fn fileExists(b: *std.Build, path: []const u8) bool {
    b.build_root.handle.access(b.graph.io, path, .{}) catch return false;
    return true;
}

fn amoSecretConfigured(b: *std.Build, path: []const u8) bool {
    const contents = b.build_root.handle.readFileAlloc(b.graph.io, path, b.allocator, .limited(16 * 1024)) catch {
        return false;
    };

    const has_issuer = hasNonEmptyJsonString(contents, "\"issuer\"") or
        hasNonEmptyJsonString(contents, "\"jwt_issuer\"") or
        hasNonEmptyJsonString(contents, "\"api_key\"") or
        hasNonEmptyJsonString(contents, "\"key\"") or
        hasNonEmptyJsonString(contents, "\"jwt_key\"");
    const has_secret = hasNonEmptyJsonString(contents, "\"secret\"") or
        hasNonEmptyJsonString(contents, "\"jwt_secret\"") or
        hasNonEmptyJsonString(contents, "\"api_secret\"") or
        hasNonEmptyJsonString(contents, "\"hmac_secret\"");

    return has_issuer and has_secret;
}

fn hasNonEmptyJsonString(contents: []const u8, field_name: []const u8) bool {
    const field_index = std.mem.indexOf(u8, contents, field_name) orelse return false;
    const after_field = contents[field_index + field_name.len ..];
    const colon_index = std.mem.indexOfScalar(u8, after_field, ':') orelse return false;
    const after_colon = std.mem.trim(u8, after_field[colon_index + 1 ..], " \t\r\n");

    if (after_colon.len == 0 or after_colon[0] != '"') return false;

    const string_body = after_colon[1..];
    const closing_quote_index = std.mem.indexOfScalar(u8, string_body, '"') orelse return false;
    const trimmed_value = std.mem.trim(u8, string_body[0..closing_quote_index], " \t\r\n");

    return trimmed_value.len > 0;
}
