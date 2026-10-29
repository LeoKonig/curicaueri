#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "AWS::aws-c-common" for configuration "Release"
set_property(TARGET AWS::aws-c-common APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(AWS::aws-c-common PROPERTIES
  IMPORTED_LOCATION_RELEASE "/nix/store/6cqd5cpqm7flgpi0fl4003j4ys5hja6v-aws-c-common-0.12.4/lib/libaws-c-common.so.1.0.0"
  IMPORTED_SONAME_RELEASE "libaws-c-common.so.1"
  )

list(APPEND _cmake_import_check_targets AWS::aws-c-common )
list(APPEND _cmake_import_check_files_for_AWS::aws-c-common "/nix/store/6cqd5cpqm7flgpi0fl4003j4ys5hja6v-aws-c-common-0.12.4/lib/libaws-c-common.so.1.0.0" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
