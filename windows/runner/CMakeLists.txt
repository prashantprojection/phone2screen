cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "studio_bridge.cpp"
  "studio_bridge.h"
  "utils.cpp"
  "vcam_registry.cpp"
  "vcam_registry.h"
  "vcam_shared_mem.h"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE
  "dwmapi.lib"
  "ole32.lib"
  "oleaut32.lib"
  "strmiids.lib"
  "winmm.lib"
)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# DirectShow zero-OBS virtual camera COM DLL (`p2s_vcam.dll`).
add_library(p2s_vcam SHARED
  "vcam_dll.cpp"
  "vcam_dll.def"
  "vcam_filter.cpp"
  "vcam_filter.h"
  "vcam_pin.cpp"
  "vcam_pin.h"
  "vcam_registry.cpp"
  "vcam_registry.h"
  "vcam_shared_mem.h"
)
apply_standard_settings(p2s_vcam)
target_compile_definitions(p2s_vcam PRIVATE "NOMINMAX")
target_include_directories(p2s_vcam PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(p2s_vcam PRIVATE
  "ole32.lib"
  "oleaut32.lib"
  "strmiids.lib"
  "uuid.lib"
  "advapi32.lib"
  "gdi32.lib"
)
add_dependencies(${BINARY_NAME} p2s_vcam)
