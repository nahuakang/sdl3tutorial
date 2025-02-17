#import "Basic";
#import "File";
#import "Math";
sdl :: #import "SDL3";
img :: #import "SDL3/image";


// Constants
rotation_speed :: 90.0 * PI / 180.0;
screen_width  :: 640;
screen_height :: 480;


// Global variables
window: *sdl.Window;


load_shader :: (device: *sdl.GPU_Device, shader_code: string, stage: sdl.GPU_Shader_Stage, num_uniform_buffers: u32) -> *sdl.GPU_Shader {
    create_info := sdl.GPU_Shader_Create_Info.{
        code_size           = cast(u64) shader_code.count,
        code                = shader_code.data,
        entry_point         ="main",
        format              = .SPIRV,
        stage               = stage,
        num_uniform_buffers = num_uniform_buffers,
    };
    return sdl.create_gpu_shader(device, *create_info);
}


main :: () {
    // Load shader code
    frag_shader_code := read_entire_file("shaders/shader.spv.frag");
    vert_shader_code := read_entire_file("shaders/shader.spv.vert");

    // Set up SDL
    ok     := sdl.init(.VIDEO); assert(ok);
    window  = sdl.create_window("Tutorial", screen_width, screen_height, xx 0); assert(window != null);
    gpu    := sdl.create_gpu_device(.SPIRV, true, null); assert(gpu != null);
    ok      = sdl.claim_window_for_gpu_device(gpu, window); assert(ok);

    // Load shaders
    vert_shader := load_shader(gpu, shader_code=vert_shader_code, stage=.VERTEX, num_uniform_buffers=1);
    frag_shader := load_shader(gpu, shader_code=frag_shader_code, stage=.FRAGMENT, num_uniform_buffers=0);

    // Set up pipeline
    color_desc := sdl.GPU_Color_Target_Description.{
        format = sdl.get_gpu_swapchain_texture_format(gpu, window),
    };
    create_info := sdl.GPU_Graphics_Pipeline_Create_Info.{
        vertex_shader   = vert_shader,
        fragment_shader = frag_shader,
        primitive_type  = .TRIANGLELIST,
        target_info     = sdl.GPU_Graphics_Pipeline_Target_Info.{
            color_target_descriptions = *color_desc,
            num_color_targets         = 1,
        },
    };
    pipeline := sdl.create_gpu_graphics_pipeline(gpu, *create_info);

    // Release shaders
    sdl.release_gpu_shader(gpu, vert_shader);
    sdl.release_gpu_shader(gpu, frag_shader);

    WindowSize :: struct {
        x: s32;
        y: s32;
    };

    window_size: WindowSize;
    ok = sdl.get_window_size(window, *window_size.x, *window_size.y); assert(ok);

    // MVP data
    rotation := 0.0;  // in radians
    proj_mat := make_projection_matrix(
        70 * PI / 180.0,  // fov_vertical in radians (convert from 70 degrees)
        cast(float) window_size.x / cast(float) window_size.y,  // aspect_ratio
        0.0001,  // z_near
        1000.0,   // z_far
    );

    UBO :: struct {
        mvp: Matrix4;
    }

    last_ticks: u64 = sdl.get_ticks();

    event: sdl.Event;
    while eventloop := true {
        new_ticks: u64 = sdl.get_ticks();
        delta_time := (cast(float) (new_ticks - last_ticks)) / 1000.0;
        last_ticks = new_ticks;

        // Process events
        while sdl.poll_event(*event) {
            if event.type == {
                case .QUIT;
                    break eventloop;
                case .KEY_DOWN;
                    if event.key.scancode == .ESCAPE then break eventloop;
            }
        }

        // Update game state

        // Render
        cmd_buf := sdl.acquire_gpu_command_buffer(gpu);

        swapchain_tex: *sdl.GPU_Texture;
        ok = sdl.wait_and_acquire_gpu_swapchain_texture(cmd_buf, window, *swapchain_tex, null, null); assert(ok);

        // Prepare ubo uniform data
        rotation += rotation_speed * delta_time;
        pos := Vector3.{0, 0, -5};
        translate_mat := translate(Matrix4_Identity, pos);
        q: Quaternion;
        set_from_axis_and_angle(*q, 0, 1, 0, rotation);  // Set rotation around Y axis
        model_mat := translate_mat * rotation_matrix(Matrix4, q);
        ubo := UBO.{ mvp = proj_mat * model_mat };

        // swapchain_tex might be null (e.g. when minimizing the window)
        if swapchain_tex != null {
            color_target   := sdl.GPU_Color_Target_Info.{
                texture     = swapchain_tex,
                load_op     = .CLEAR,
                clear_color = .{0, 0.2, 0.4, 1},
                store_op    = .STORE,
            };
            render_pass := sdl.begin_gpu_render_pass(cmd_buf, *color_target, 1, null);

            sdl.bind_gpu_graphics_pipeline(render_pass, pipeline);
            // Vertex attributes - per vertex
            // Uniform data: command_buffer, binding number (slot index),
            sdl.push_gpu_vertex_uniform_data(cmd_buf, 0, *ubo, size_of(UBO));
            sdl.draw_gpu_primitives(render_pass, 3, 1, 0, 0);
            sdl.end_gpu_render_pass(render_pass);
        } else {
            // log("Not rendering\n");
        }

        ok = sdl.submit_gpu_command_buffer(cmd_buf); assert(ok);
    }
}
