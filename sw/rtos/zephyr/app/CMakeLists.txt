# eRISCV-M2 Zephyr sample application — CMakeLists.txt
# Copyright (c) 2024 eRISCV-MCU Contributors
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(eriscv_m2_zephyr)

target_sources(app PRIVATE src/main.c)
