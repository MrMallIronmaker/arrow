# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

add_arrow_example(row_wise_conversion_example)

if(ARROW_COMPUTE)
  add_arrow_example(compute_register_example)
endif()

if(ARROW_ENGINE)
  add_arrow_example(engine_substrait_consumption EXTRA_LINK_LIBS arrow_engine_shared)
endif()

if(ARROW_COMPUTE AND ARROW_CSV)
  add_arrow_example(compute_and_write_csv_example)
endif()

if(ARROW_FLIGHT)
  # Static gRPC means we cannot linked to shared Arrow, since then
  # we'll violate ODR for gRPC symbols
  if(ARROW_GRPC_USE_SHARED)
    set(FLIGHT_EXAMPLES_LINK_LIBS arrow_flight_shared)
    # We don't directly use symbols from the reflection library, so
    # ensure the linker still links to it
    set(GRPC_REFLECTION_LINK_LIBS -Wl,--no-as-needed gRPC::grpc++_reflection
                                  -Wl,--as-needed)
  elseif(NOT ARROW_BUILD_STATIC)
    message(FATAL_ERROR "Statically built gRPC requires ARROW_BUILD_STATIC=ON")
  else()
    set(FLIGHT_EXAMPLES_LINK_LIBS arrow_flight_static)
    if(APPLE)
      set(GRPC_REFLECTION_LINK_LIBS -Wl,-force_load gRPC::grpc++_reflection)
    else()
      set(GRPC_REFLECTION_LINK_LIBS -Wl,--whole-archive gRPC::grpc++_reflection
                                    -Wl,--no-whole-archive)
    endif()
  endif()

  set(FLIGHT_EXAMPLE_GENERATED_PROTO_FILES
      "${CMAKE_CURRENT_BINARY_DIR}/helloworld.pb.cc"
      "${CMAKE_CURRENT_BINARY_DIR}/helloworld.pb.h"
      "${CMAKE_CURRENT_BINARY_DIR}/helloworld.grpc.pb.cc"
      "${CMAKE_CURRENT_BINARY_DIR}/helloworld.grpc.pb.h")
  set_source_files_properties(${FLIGHT_EXAMPLE_GENERATED_PROTO_FILES} PROPERTIES GENERATED
                                                                                 TRUE)

  set(FLIGHT_EXAMPLE_PROTO "helloworld.proto")
  set(FLIGHT_EXAMPLE_PROTO_PATH "${CMAKE_CURRENT_LIST_DIR}")
  set(FLIGHT_EXAMPLE_PROTO_DEPENDS ${FLIGHT_EXAMPLE_PROTO} gRPC::grpc_cpp_plugin)

  add_custom_command(OUTPUT ${FLIGHT_EXAMPLE_GENERATED_PROTO_FILES}
                     COMMAND ${ARROW_PROTOBUF_PROTOC} "-I${FLIGHT_EXAMPLE_PROTO_PATH}"
                             "--cpp_out=${CMAKE_CURRENT_BINARY_DIR}"
                             "${FLIGHT_EXAMPLE_PROTO}"
                     COMMAND ${ARROW_PROTOBUF_PROTOC} "-I${FLIGHT_EXAMPLE_PROTO_PATH}"
                             "--grpc_out=${CMAKE_CURRENT_BINARY_DIR}"
                             "--plugin=protoc-gen-grpc=$<TARGET_FILE:gRPC::grpc_cpp_plugin>"
                             "${FLIGHT_EXAMPLE_PROTO}"
                     DEPENDS ${FLIGHT_EXAMPLE_PROTO_DEPENDS})

  add_custom_target(flight_grpc_example_gen ALL
                    DEPENDS ${FLIGHT_EXAMPLE_GENERATED_PROTO_FILES})

  add_arrow_example(flight_grpc_example
                    DEPENDENCIES
                    flight_grpc_example_gen
                    # Not CMAKE_CURRENT_BINARY_DIR so we can #include
                    # "examples/arrow/helloworld.pb.h" instead of
                    # "helloworld.pb.h" (which fails lint)
                    EXTRA_INCLUDES
                    ${CMAKE_BINARY_DIR}
                    EXTRA_LINK_LIBS
                    ${FLIGHT_EXAMPLES_LINK_LIBS}
                    gRPC::grpc++
                    ${GRPC_REFLECTION_LINK_LIBS}
                    ${ARROW_PROTOBUF_LIBPROTOBUF}
                    ${GFLAGS_LIBRARIES}
                    EXTRA_SOURCES
                    "${CMAKE_CURRENT_BINARY_DIR}/helloworld.pb.cc"
                    "${CMAKE_CURRENT_BINARY_DIR}/helloworld.grpc.pb.cc")

  if(ARROW_FLIGHT_SQL)
    if(ARROW_GRPC_USE_SHARED)
      set(FLIGHT_SQL_EXAMPLES_LINK_LIBS arrow_flight_sql_shared)
    else()
      set(FLIGHT_SQL_EXAMPLES_LINK_LIBS arrow_flight_sql_static)
    endif()

    add_arrow_example(flight_sql_example
                      DEPENDENCIES
                      flight-sql-test-server
                      EXTRA_LINK_LIBS
                      ${FLIGHT_EXAMPLES_LINK_LIBS}
                      ${FLIGHT_SQL_EXAMPLES_LINK_LIBS}
                      gRPC::grpc++
                      ${ARROW_PROTOBUF_LIBPROTOBUF}
                      ${GFLAGS_LIBRARIES})
  endif()
endif()

if(ARROW_PARQUET AND ARROW_DATASET)
  if(ARROW_BUILD_SHARED)
    set(DATASET_EXAMPLES_LINK_LIBS arrow_dataset_shared)
  else()
    set(DATASET_EXAMPLES_LINK_LIBS arrow_dataset_static)
  endif()

  add_arrow_example(dataset_parquet_scan_example EXTRA_LINK_LIBS
                    ${DATASET_EXAMPLES_LINK_LIBS})
  add_dependencies(dataset-parquet-scan-example parquet)

  add_arrow_example(dataset_documentation_example EXTRA_LINK_LIBS
                    ${DATASET_EXAMPLES_LINK_LIBS})
  add_dependencies(dataset-documentation-example parquet)

  add_arrow_example(execution_plan_documentation_examples EXTRA_LINK_LIBS
                    ${DATASET_EXAMPLES_LINK_LIBS})
  add_dependencies(execution-plan-documentation-examples parquet)

  add_arrow_example(join_example EXTRA_LINK_LIBS ${DATASET_EXAMPLES_LINK_LIBS})
  add_dependencies(join-example parquet)
endif()
