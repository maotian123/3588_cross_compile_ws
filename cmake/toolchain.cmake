# RK3588 aarch64 Ubuntu 20.04 / ROS1 Noetic cross compile toolchain.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_LIBRARY_ARCHITECTURE aarch64-linux-gnu)

get_filename_component(_TOOLCHAIN_CMAKE_DIR "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(_WORKSPACE_DIR "${_TOOLCHAIN_CMAKE_DIR}/.." ABSOLUTE)

if(DEFINED ENV{RK3588_CROSS_COMPILE_SYSROOT})
    set(CMAKE_SYSROOT "$ENV{RK3588_CROSS_COMPILE_SYSROOT}")
else()
    message(FATAL_ERROR "RK3588_CROSS_COMPILE_SYSROOT is not set. Run: source cross_compile_env.sh")
endif()

set(_TOOLCHAIN_BIN_CANDIDATES
    "${_WORKSPACE_DIR}/toolchain/bin"
    "$ENV{RK3588_TOOLCHAIN_DIR}/bin"
    "$ENV{RK3588_TOOLCHAIN_DIR}"
)

find_program(_RK3588_C_COMPILER
    NAMES aarch64-linux-gnu-gcc aarch64-buildroot-linux-gnu-gcc
    PATHS ${_TOOLCHAIN_BIN_CANDIDATES}
    NO_DEFAULT_PATH
)
find_program(_RK3588_CXX_COMPILER
    NAMES aarch64-linux-gnu-g++ aarch64-buildroot-linux-gnu-g++
    PATHS ${_TOOLCHAIN_BIN_CANDIDATES}
    NO_DEFAULT_PATH
)

if(NOT _RK3588_C_COMPILER)
    find_program(_RK3588_C_COMPILER NAMES aarch64-linux-gnu-gcc aarch64-buildroot-linux-gnu-gcc)
endif()
if(NOT _RK3588_CXX_COMPILER)
    find_program(_RK3588_CXX_COMPILER NAMES aarch64-linux-gnu-g++ aarch64-buildroot-linux-gnu-g++)
endif()

if(NOT _RK3588_C_COMPILER OR NOT _RK3588_CXX_COMPILER)
    message(FATAL_ERROR
        "aarch64 GCC toolchain not found. Install gcc-aarch64-linux-gnu/g++-aarch64-linux-gnu "
        "or put a toolchain under ${_WORKSPACE_DIR}/toolchain/bin.")
endif()

set(CMAKE_C_COMPILER "${_RK3588_C_COMPILER}" CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER "${_RK3588_CXX_COMPILER}" CACHE FILEPATH "" FORCE)

set(CMAKE_FIND_ROOT_PATH
    "${_WORKSPACE_DIR}/install"
    "${CMAKE_SYSROOT}"
    "${CMAKE_SYSROOT}/opt/ros/noetic"
    "${CMAKE_SYSROOT}/usr"
    "${CMAKE_SYSROOT}/usr/local"
)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

list(APPEND CMAKE_LIBRARY_PATH
    "${_WORKSPACE_DIR}/install/lib"
    "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu"
    "${CMAKE_SYSROOT}/lib/aarch64-linux-gnu"
    "${CMAKE_SYSROOT}/usr/lib"
    "${CMAKE_SYSROOT}/usr/local/lib"
    "${CMAKE_SYSROOT}/opt/ros/noetic/lib"
)

set(_SYSROOT_LIB "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu")
set(_SYSROOT_BASE_LIB "${CMAKE_SYSROOT}/lib/aarch64-linux-gnu")
set(_USR_LIB "${CMAKE_SYSROOT}/usr/lib")
set(_LOCAL_LIB "${CMAKE_SYSROOT}/usr/local/lib")
set(_ROS_LIB "${CMAKE_SYSROOT}/opt/ros/noetic/lib")
set(_INSTALL_LIB "${_WORKSPACE_DIR}/install/lib")

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} --sysroot=${CMAKE_SYSROOT} -D_GNU_SOURCE" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} --sysroot=${CMAKE_SYSROOT} -D_GNU_SOURCE -DBOOST_THREAD_POSIX -Wno-class-memaccess" CACHE STRING "" FORCE)

set(_RK3588_LINK_FLAGS
    "--sysroot=${CMAKE_SYSROOT} -L${_SYSROOT_LIB} -L${_SYSROOT_BASE_LIB} -L${_USR_LIB} -L${_LOCAL_LIB} -L${_ROS_LIB} -L${_INSTALL_LIB} -Wl,--allow-shlib-undefined,-rpath-link,${_INSTALL_LIB},-rpath-link,${_SYSROOT_LIB},-rpath-link,${_SYSROOT_BASE_LIB},-rpath-link,${_USR_LIB},-rpath-link,${_LOCAL_LIB},-rpath-link,${_ROS_LIB}"
)
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${_RK3588_LINK_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${_RK3588_LINK_FLAGS}" CACHE STRING "" FORCE)

set(ENV{PKG_CONFIG_SYSROOT_DIR} "${CMAKE_SYSROOT}")
set(ENV{PKG_CONFIG_LIBDIR}
    "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/pkgconfig:${CMAKE_SYSROOT}/usr/lib/pkgconfig:${CMAKE_SYSROOT}/usr/share/pkgconfig:${CMAKE_SYSROOT}/usr/local/lib/pkgconfig:${CMAKE_SYSROOT}/opt/ros/noetic/lib/pkgconfig"
)
set(ENV{PKG_CONFIG_PATH} "$ENV{PKG_CONFIG_LIBDIR}")

set(BOOST_ROOT "${CMAKE_SYSROOT}/usr" CACHE PATH "" FORCE)
set(Boost_INCLUDE_DIR "${CMAKE_SYSROOT}/usr/include" CACHE PATH "" FORCE)
set(Boost_LIBRARY_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu" CACHE PATH "" FORCE)
set(Boost_NO_SYSTEM_PATHS ON CACHE BOOL "" FORCE)
set(Boost_NO_BOOST_CMAKE ON CACHE BOOL "" FORCE)

set(EIGEN3_INCLUDE_DIR "${CMAKE_SYSROOT}/usr/include/eigen3" CACHE PATH "" FORCE)
set(Eigen3_DIR "${CMAKE_SYSROOT}/usr/share/eigen3/cmake" CACHE PATH "" FORCE)
include_directories("${EIGEN3_INCLUDE_DIR}")

set(PCL_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/cmake/pcl" CACHE PATH "" FORCE)
set(OpenCV_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/cmake/opencv4" CACHE PATH "" FORCE)
set(GeographicLib_DIR "${CMAKE_SYSROOT}/usr/share/cmake/geographiclib" CACHE PATH "" FORCE)
set(yaml-cpp_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/cmake/yaml-cpp" CACHE PATH "" FORCE)
set(Sophus_DIR "${CMAKE_SYSROOT}/usr/local/share/sophus/cmake" CACHE PATH "" FORCE)

set(Qt5_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/cmake/Qt5" CACHE PATH "" FORCE)
set(Qt5Widgets_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/cmake/Qt5Widgets" CACHE PATH "" FORCE)
set(Qt5OpenGL_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/cmake/Qt5OpenGL" CACHE PATH "" FORCE)
set(Qt5Charts_DIR "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/cmake/Qt5Charts" CACHE PATH "" FORCE)
set(QT_QMAKE_EXECUTABLE "/usr/bin/qmake" CACHE FILEPATH "" FORCE)

set(Python3_EXECUTABLE /usr/bin/python3 CACHE FILEPATH "" FORCE)
set(Python3_INCLUDE_DIR "${CMAKE_SYSROOT}/usr/include/python3.8" CACHE PATH "" FORCE)
set(Python3_LIBRARY "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/libpython3.8.so" CACHE FILEPATH "" FORCE)
set(PYTHON_SOABI "cpython-38-aarch64-linux-gnu" CACHE STRING "" FORCE)
set(PYBIND11_PYTHON_VERSION 3.8 CACHE STRING "" FORCE)
set(PYBIND11_FINDPYTHON ON CACHE BOOL "" FORCE)

set(SM_RUN_RESULT 0 CACHE STRING "" FORCE)
set(SM_RUN_RESULT__TRYRUN_OUTPUT "PTHREAD_RWLOCK_PREFER_READER_NP" CACHE STRING "" FORCE)
set(USE_THIRDPARTY_SHARED_MUTEX OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
