cmake_minimum_required(VERSION 3.22.1)
project(koto_libcxx LANGUAGES CXX)

# Empty shared lib linked against c++_shared so AGP packages libc++_shared.so.
# NumPy / OpenCV / TFLite Python wheels dlopen it from the APK namespace.
add_library(koto_libcxx SHARED libcxx_stub.cpp)
