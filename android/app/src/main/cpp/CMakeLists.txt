cmake_minimum_required(VERSION 3.22.1)
project(scrapyard_libcxx LANGUAGES CXX)

# Empty shared lib linked against c++_shared so AGP packages libc++_shared.so.
# NumPy / OpenCV / TFLite Python wheels dlopen it from the APK namespace.
add_library(scrapyard_libcxx SHARED libcxx_stub.cpp)
# 16 KB ELF alignment for Play's Android 15+ page-size requirement.
target_link_options(scrapyard_libcxx PRIVATE "-Wl,-z,max-page-size=16384")
