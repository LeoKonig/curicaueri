#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "AWS::aws-c-sdkutils" for configuration "Release"
set_property(TARGET AWS::aws-c-sdkutils APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(AWS::aws-c-sdkutils PROPERTIES
  IMPORTED_LOCATION_RELEASE "/nix/store/ydlz78x3ahgclpd3y8c1hvmcns8a3wb4-aws-c-sdkutils-0.2.4/lib/libaws-c-sdkutils.so.1.0.0"
  IMPORTED_SONAME_RELEASE "libaws-c-sdkutils.so.1.0.0"
  )

list(APPEND _cmake_import_check_targets AWS::aws-c-sdkutils )
list(APPEND _cmake_import_check_files_for_AWS::aws-c-sdkutils "/nix/store/ydlz78x3ahgclpd3y8c1hvmcns8a3wb4-aws-c-sdkutils-0.2.4/lib/libaws-c-sdkutils.so.1.0.0" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
