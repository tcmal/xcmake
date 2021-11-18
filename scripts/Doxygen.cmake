include(IncludeGuard)
include_guard()

function(add_cppreference_tagfile)
    if (TARGET cppreference_tagfile)
        return()
    endif()
    add_subdirectory("${XCMAKE_TOOLS_DIR}/doxygen/externaltags/cppreference" "${CMAKE_BINARY_DIR}/tagfiles/cppreference")
endfunction()

function(add_nvcuda_tagfile)
    if (TARGET nvcuda_tagfile)
        return()
    endif()

    add_subdirectory("${XCMAKE_TOOLS_DIR}/doxygen/externaltags/nvcuda" "${CMAKE_BINARY_DIR}/tagfiles/nvcuda")

    add_cppreference_tagfile()
    add_dependencies(nvcuda_tagfile cppreference_tagfile)
endfunction()

define_property(TARGET
    PROPERTY DOXYGEN_INSTALL_DESTINATION
    BRIEF_DOCS "Relative install path for a Doxygen target"
    FULL_DOCS "Relative install path for a Doxygen target"
)
define_property(TARGET
    PROPERTY DOXYGEN_HEADER_TARGETS
    BRIEF_DOCS "The header targets consumed by a Doxygen target."
    FULL_DOCS "The header targets consumed by a Doxygen target."
)
define_property(TARGET
    PROPERTY DOXYGEN_TAGFILE
    BRIEF_DOCS "The tagfile generated by this Doxygen target."
    FULL_DOCS "The tagfile generated by this Doxygen target."
)

# Generate Doxygen documentation, attached to a new target with the given name.
# The generated target will create documentation covering the provided HEADER_TARGETS, previously created with
# `add_headers()`.
function(add_doxygen TARGET)
    # Don't bother if docs are disabled
    ensure_docs_enabled()

    find_package(Doxygen)
    if (NOT DOXYGEN_FOUND)
        message(BOLD_YELLOW "Skipping doxygen target ${TARGET} because `doxygen` could not be found.")
        return()
    endif()

    # Oh, the argparse boilerplate
    set(flags NOINSTALL CUDA)
    set(oneValueArgs INSTALL_DESTINATION DOXYFILE LAYOUT_FILE DOXYFILE_SUFFIX LOGO SUBJECT)
    set(multiValueArgs HEADER_TARGETS DEPENDS INPUT_HEADERS EXTRA_EXAMPLE_PATHS ENABLED_SECTIONS PREDEFINED FILTER)
    cmake_parse_arguments("d" "${flags}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    default_value(d_INSTALL_DESTINATION "docs/${TARGET}")
    default_value(d_DOXYFILE_SUFFIX "Doxyfile.suffix")
    configure_file("${d_DOXYFILE_SUFFIX}" "${CMAKE_CURRENT_BINARY_DIR}/${TARGET}${d_DOXYFILE_SUFFIX}" @ONLY)

    # This variable affects a configure_file call later on, effectively including the suffix file at the end of the
    # Doxyfile.in template shipped with XCMake.
    file(READ "${CMAKE_CURRENT_BINARY_DIR}/${TARGET}${d_DOXYFILE_SUFFIX}" DOXYFILE_SUFFIX_PAYLOAD)
    string(TOLOWER "${d_SUBJECT}" LOWER_LIB_NAME)

    # The EXAMPLES_PATH parameter for the Doxyfile.
    set(EXAMPLE_PATH "")
    if (EXISTS "${CMAKE_CURRENT_LIST_DIR}/test")
        set(EXAMPLE_PATH "\"${CMAKE_CURRENT_LIST_DIR}/test\"")
    endif()

    foreach (P ${d_EXTRA_EXAMPLE_PATHS})
        set(EXAMPLE_PATH "${EXAMPLE_PATH} \"${CMAKE_CURRENT_LIST_DIR}/${P}\"")
    endforeach ()

    # Extract the list of input paths from the list of given header targets, and build a list of all the header files
    # Doxygen is about to process, so we can add them as dependencies.
    set(DOXYGEN_INPUTS "")
    set(DOXYGEN_INPUT_DIRS "")
    set(HEADERS_USED "")
    foreach (T ${d_HEADER_TARGETS})
        # Pick up the ORIGINAL_SOURCES property from the custom target that add_headers() creates.
        get_target_property(NEW_HEADERS ${T}_ALL ORIGINAL_SOURCES)

        foreach(NEW_HEADER ${NEW_HEADERS})
            get_filename_component(NEW_DIR ${NEW_HEADER} DIRECTORY)
            set(DOXYGEN_INPUTS "${DOXYGEN_INPUTS} \"${NEW_HEADER}\"")
            set(DOXYGEN_INPUT_DIRS "${DOXYGEN_INPUT_DIRS} \"${NEW_DIR}\"")

            list(APPEND HEADERS_USED ${NEW_HEADER})
        endforeach()
    endforeach ()

    # Add things that were specified as single-file inputs
    foreach (NEW_HEADER ${d_INPUT_HEADERS})
        get_filename_component(NEW_DIR ${NEW_HEADER} DIRECTORY)
        set(DOXYGEN_INPUTS "${DOXYGEN_INPUTS} \"${NEW_HEADER}\"")
        set(DOXYGEN_INPUT_DIRS "${DOXYGEN_INPUT_DIRS} \"${NEW_DIR}\"")
        list(APPEND HEADERS_USED ${NEW_HEADER})
    endforeach()

    # Add the things we always include.
    set(DOXYGEN_INPUTS "${DOXYGEN_INPUTS} \"${XCMAKE_TOOLS_DIR}/doxygen/include\"")
    set(DOXYGEN_INPUT_DIRS "${DOXYGEN_INPUT_DIRS} \"${XCMAKE_TOOLS_DIR}/doxygen/include\"")

    # The tagfile we're going to generate. This could be tweaked to allow the caller to specify the output path...
    # This must be quoted in the Doxyfile, but we don't put the quotes in it here because we need the _actual file name_
    # in the cmake variable. This is in contrast to some other variables below.
    set(OUT_TAGFILE "${CMAKE_BINARY_DIR}/docs/tagfiles/${TARGET}.tag")
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/docs/tagfiles")

    add_custom_target(${TARGET}
        # The tagfile is a convenient output file to use for dependency tracking.
        DEPENDS "${OUT_TAGFILE}"
    )
    set_target_properties(${TARGET} PROPERTIES
        DOXYGEN_INSTALL_DESTINATION "${COMPONENT_INSTALL_ROOT}${d_INSTALL_DESTINATION}"
        DOXYGEN_HEADER_TARGETS "${d_HEADER_TARGETS}"
        DOXYGEN_TAGFILE "${OUT_TAGFILE}"
    )

    # The cppreference tagfile.
    add_cppreference_tagfile()
    set(DEPENDS "${d_DEPENDS}" cppreference_tagfile)

    # If we're doxygenating a CUDA target, make sure the NVCUDA crossreference target is registered.
    if (d_CUDA)
        add_nvcuda_tagfile()
        set(DEPENDS "${DEPENDS}" nvcuda_tagfile)
    endif ()

    # Collect up the tagfiles for the other doxygen targets we depend on.
    set(TAGFILES)
    foreach (DT ${DEPENDS})
        add_dependencies(${TARGET} ${DT})

        get_target_property(DEPENDEE_TAGFILE ${DT} DOXYGEN_TAGFILE)
        get_target_property(DEPENDEE_INSTALL_DESTINATION ${DT} DOXYGEN_INSTALL_DESTINATION)
        get_target_property(DEPENDEE_URL ${DT} DOXYGEN_URL)

        if (NOT "${DEPENDEE_INSTALL_DESTINATION}" STREQUAL "DEPENDEE_INSTALL_DESTINATION-NOTFOUND")
            path_to_slashes("${DEPENDEE_INSTALL_DESTINATION}" DEST_DOTSLASHES)

            # An extra `../` is added to cancel out the `./html` directory inserted by Doxygen.
            set(TD_TAGFILE "${DEPENDEE_TAGFILE}=${DEST_DOTSLASHES}../${DEPENDEE_INSTALL_DESTINATION}/html")
        elseif (NOT "${DEPENDEE_URL}" STREQUAL "${DEPENDEE_URL}-NOTFOUND")
            set(TD_TAGFILE "${DEPENDEE_TAGFILE}=${DEPENDEE_URL}")
        else()
            message(FATAL_ERROR "Dependency documentation ${DT} of ${TARGET} has no generated or published location!")
        endif()

        set(TAGFILES "${TAGFILES} \"${TD_TAGFILE}\"")
    endforeach()

    # Build the filter. The FILTER arguments are passed verbatim to input_filter.py. See that script for its arguments.
    # The input path given to the script is absolute.
    find_package(Python3 3.8 REQUIRED COMPONENTS Interpreter)
    set(DOXYGEN_INPUT_FILTER
        "\\\"${Python3_EXECUTABLE}\\\" \\\"${XCMAKE_TOOLS_DIR}/doxygen/input_filter.py\\\" \\\"-c\\\" \\\"${CMAKE_CXX_COMPILER}\\\"")

    foreach (A IN LISTS d_FILTER)
        set(DOXYGEN_INPUT_FILTER "${DOXYGEN_INPUT_FILTER} \\\"${A}\\\"")
    endforeach()

    # More configuration variables.
    set(DOXYGEN_LAYOUT_FILE "${XCMAKE_TOOLS_DIR}/doxygen/DoxygenLayout.xml")
    set(DOXYGEN_HTML_HEADER_FILE "${XCMAKE_TOOLS_DIR}/doxygen/spectral_doc_header.html")
    set(DOXYGEN_HTML_FOOTER_FILE "${XCMAKE_TOOLS_DIR}/doxygen/spectral_doc_footer.html")
    set(DOXYGEN_HTML_STYLE_FILE "${XCMAKE_TOOLS_DIR}/doxygen/spectral_doc_style.css")
    set(DOXYFILE "${XCMAKE_TOOLS_DIR}/doxygen/Doxyfile.in")

    # Generate the final Doxyfile, injecting the variables we calculated above (notably including the list of inputs...)
    configure_file(${DOXYFILE} "${CMAKE_CURRENT_BINARY_DIR}/Doxyfile" @ONLY)
    configure_file(${DOXYGEN_HTML_HEADER_FILE} "${CMAKE_CURRENT_BINARY_DIR}/spectral_doc_header.html" @ONLY)
    configure_file(${DOXYGEN_HTML_FOOTER_FILE} "${CMAKE_CURRENT_BINARY_DIR}/spectral_doc_footer.html" @ONLY)
    configure_file(${DOXYGEN_HTML_STYLE_FILE} "${CMAKE_CURRENT_BINARY_DIR}/spectral_doc_style.css" @ONLY)

    # Add a target for the tagfile, the main target ${TARGET} will depend on it.
    # Command to actually run doxygen, depending on every header file and the doxyfile template.
    add_custom_command(
        OUTPUT "${OUT_TAGFILE}"
        COMMAND doxygen
        COMMENT "Doxygenation of ${TARGET}..."
        DEPENDS
            "${CMAKE_CURRENT_BINARY_DIR}/Doxyfile"
            ${HEADERS_USED} # <- This one deliberately not quoted.
            "${DOXYGEN_LAYOUT_FILE}"
            "${CMAKE_CURRENT_BINARY_DIR}/spectral_doc_header.html"
            "${CMAKE_CURRENT_BINARY_DIR}/spectral_doc_footer.html"
            "${CMAKE_CURRENT_BINARY_DIR}/spectral_doc_style.css"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    )

    if (NOT "${d_NOINSTALL}")
        # Make the new thing get built by `make docs`
        add_dependencies(docs ${TARGET})

        install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/doxygen/" DESTINATION "${d_INSTALL_DESTINATION}")
    endif()
endfunction()
