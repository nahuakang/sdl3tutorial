#import "Basic";
#import "Compiler";
#import "File_Utilities";
#import "Process";
#import "String";


get_shader_extension :: (path: string) -> (input_extension: string, output_extension: string) {
    if ends_with(path, ".glsl.vert") return ".glsl.vert", ".vert";
    if ends_with(path, ".glsl.frag") return ".glsl.frag", ".frag";

    return "", "";
}


remove_extension :: (path: string, extension: string) -> string {
    if ends_with(path, extension) {
        return slice(path, 0, path.count - extension.count);
    }

    return path;
}


compile_shader :: (shader_path: string, output_path: string) -> bool {
    args: [..]string;
    array_add(*args, "C:/VulkanSDK/1.4.304.1/Bin/glslc");
    array_add(*args, shader_path);
    array_add(*args, "-o");
    array_add(*args, output_path);

    result := run_command(..args);
    if result.exit_code != 0 {
        log("Error compiling shader %: %\n", shader_path, result.type);
        return false;
    }

    return true;
}


compile_shaders :: (shader_dir: string, output_dir: string) {
    shader_files := file_list(shader_dir, recursive=true);

    for shader_file: shader_files {
        if !ends_with(shader_file, "glsl.vert") && !ends_with(shader_file, "glsl.frag") continue;

        input_extension, output_extension := get_shader_extension(shader_file);

        file_name := remove_extension(path_filename(shader_file), input_extension);

        output_path := join(output_dir, "/", file_name, ".spv", output_extension);
        success := compile_shader(shader_file, output_path);
        if !success {
            compiler_report(tprint("Failed to compile shader %", shader_file));
        }
    }
}


build :: () {
    w := compiler_create_workspace("SDL3Tutorial");
    if !w {
        log("Workspace creation failed.\n");
        return;
    }

    options := get_build_options(w);
    options.output_executable_name = "sdl3tutorial";

    set_build_options(options, w);
    compiler_begin_intercept(w);

    add_build_file("src/game.jai", w);

    compiler_end_intercept(w);
    set_build_options_dc(.{do_output=false});

    // Compile shaders
    compile_shaders("shaders", "shaders");
}

#run build();