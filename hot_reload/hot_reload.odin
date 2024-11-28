// Development paint exe. Loads paint.dll and reloads it whenever it changes.

package main

import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	exit: i32
	when ODIN_OS == .Windows {
		exit = libc.system(fmt.ctprintf("copy paint.dll {0}", to))
	} else {
		exit = libc.system(fmt.ctprintf("cp paint" + DLL_EXT + " {0}", to))
	}

	if exit != 0 {
		fmt.printfln("Failed to copy paint" + DLL_EXT + " to {0}", to)
		return false
	}

	return true
}

paint_API :: struct {
	lib:               dynlib.Library,
	init_window:       proc(),
	init:              proc(),
	update:            proc() -> bool,
	shutdown:          proc(),
	shutdown_window:   proc(),
	memory:            proc() -> rawptr,
	memory_size:       proc() -> int,
	hot_reloaded:      proc(mem: rawptr),
	force_reload:      proc() -> bool,
	force_restart:     proc() -> bool,
	modification_time: os.File_Time,
	api_version:       int,
}

load_paint_api :: proc(api_version: int) -> (api: paint_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name("paint" + DLL_EXT)
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln(
			"Failed getting last write time of paint" + DLL_EXT + ", error code: {1}",
			mod_time_error,
		)
		return
	}

	// NOTE: this needs to be a relative path for Linux to work.
	paint_dll_name := fmt.tprintf(
		"{0}paint_{1}" + DLL_EXT,
		"./" when ODIN_OS != .Windows else "",
		api_version,
	)
	copy_dll(paint_dll_name) or_return

	// This proc matches the names of the fields in paint_API to symbols in the
	// paint DLL. It actually looks for symbols starting with `paint_`, which is
	// why the argument `"paint_"` is there.
	_, ok = dynlib.initialize_symbols(&api, paint_dll_name, "paint_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_paint_api :: proc(api: ^paint_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf("paint_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln("Failed to remove paint_{0}" + DLL_EXT + " copy", api.api_version)
	}
}

main :: proc() {
	context.logger = log.create_console_logger()

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	paint_api_version := 0
	paint_api, paint_api_ok := load_paint_api(paint_api_version)

	if !paint_api_ok {
		fmt.println("Failed to load paint API")
		return
	}

	paint_api_version += 1
	paint_api.init_window()
	paint_api.init()

	old_paint_apis := make([dynamic]paint_API, default_allocator)

	window_open := true
	for window_open {
		window_open = paint_api.update()
		force_reload := paint_api.force_reload()
		force_restart := paint_api.force_restart()
		reload := force_reload || force_restart
		paint_dll_mod, paint_dll_mod_err := os.last_write_time_by_name("paint" + DLL_EXT)

		if paint_dll_mod_err == os.ERROR_NONE && paint_api.modification_time != paint_dll_mod {
			reload = true
		}

		if reload {
			new_paint_api, new_paint_api_ok := load_paint_api(paint_api_version)

			if new_paint_api_ok {
				force_restart =
					force_restart || paint_api.memory_size() != new_paint_api.memory_size()

				if !force_restart {
					// This does the normal hot reload

					// Note that we don't unload the old paint APIs because that
					// would unload the DLL. The DLL can contain stored info
					// such as string literals. The old DLLs are only unloaded
					// on a full reset or on shutdown.
					append(&old_paint_apis, paint_api)
					paint_memory := paint_api.memory()
					paint_api = new_paint_api
					paint_api.hot_reloaded(paint_memory)
				} else {
					// This does a full reset. That's basically like opening and
					// closing the paint, without having to restart the executable.
					//
					// You end up in here if the paint requests a full reset OR
					// if the size of the paint memory has changed. That would
					// probably lead to a crash anyways.

					paint_api.shutdown()
					reset_tracking_allocator(&tracking_allocator)

					for &g in old_paint_apis {
						unload_paint_api(&g)
					}

					clear(&old_paint_apis)
					unload_paint_api(&paint_api)
					paint_api = new_paint_api
					paint_api.init()
				}

				paint_api_version += 1
			}
		}

		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}

			// This prevents the paint from closing without you seeing the bad
			// frees. This is mostly needed because I use Sublime Text and my paint's
			// console isn't hooked up into Sublime's console properly.
			libc.getchar()
			panic("Bad free detected")
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	paint_api.shutdown()
	if reset_tracking_allocator(&tracking_allocator) {
		// This prevents the paint from closing without you seeing the memory
		// leaks. This is mostly needed because I use Sublime Text and my paint's
		// console isn't hooked up into Sublime's console properly.
		libc.getchar()
	}

	for &g in old_paint_apis {
		unload_paint_api(&g)
	}

	delete(old_paint_apis)

	paint_api.shutdown_window()
	unload_paint_api(&paint_api)
	mem.tracking_allocator_destroy(&tracking_allocator)
}

// Make paint use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
