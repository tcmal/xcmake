include(GNUInstallDirs)

# Builds on Cmake's built-in `UseSWIG` to add a few niceties:
# - Automatically harvest properties from the backing library
# - Automatically link against needed interpreters (eg. python's libraries when you ask for python)
# - Various --please-work settings.
function(add_swig_bindings_to TARGET)
    set(flags)
    set(oneValueArgs)
    set(multiValueArgs LANGUAGES SOURCES)
    cmake_parse_arguments("h" "${flags}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    find_package(SWIG)
    include(UseSWIG)

    set(SWIG_SOURCE_FILE_EXTENSIONS ".i" ".swg")
    set(CMAKE_SWIG_FLAGS "-doxygen")

    # UGH WHY ARE THESE SOURCE PROPERTIES.
    foreach (ARG IN LISTS h_SOURCES)
        set_source_files_properties(${ARG} PROPERTIES
            CPLUSPLUS ON
            SWIG_USE_TARGET_INCLUDE_DIRECTORIES ON
        )
    endforeach()

    # It turns out that naming a variable "SWIG_DIR" stops swig from working. Bravo.
    set(FUCKING_SWIG_DIR ${CMAKE_CURRENT_BINARY_DIR}/swig)

    set(SWIG_TMP ${FUCKING_SWIG_DIR}/tmp)
    file(MAKE_DIRECTORY ${SWIG_TMP})

    set(SWIG_OUT ${FUCKING_SWIG_DIR}/out)
    file(MAKE_DIRECTORY ${SWIG_OUT})

    foreach (LANG IN LISTS h_LANGUAGES)
        set(TAGFILE ${SWIG_TMP}/${LANG}_tag)

        # Where SWIG's output goes before it gets post-processed.
        file(MAKE_DIRECTORY ${SWIG_TMP}/${LANG})

        # Final location of the generated python etc. before being install'd.
        file(MAKE_DIRECTORY ${SWIG_OUT}/${LANG})
        install(DIRECTORY ${SWIG_OUT}/${LANG}
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}
        )

        # Where the generated C++ goes.
        set(SWIG_GENSRC_DIR ${SWIG_TMP}/${LANG}/cxx)
        file(MAKE_DIRECTORY ${SWIG_GENSRC_DIR})

        set(SWIG_TARGET ${TARGET}_${LANG})
        swig_add_library(${SWIG_TARGET}
            TYPE USE_BUILD_SHARED_LIBS
            LANGUAGE ${LANG}
            OUTPUT_DIR ${SWIG_TMP}/${LANG}
            OUTFILE_DIR ${SWIG_GENSRC_DIR}
            SOURCES ${h_SOURCES}
        )
        set_target_properties(${SWIG_TARGET}
            PROPERTIES WERROR OFF
            CXX_CLANG_TIDY ""
        )
        target_compile_options(${SWIG_TARGET} PRIVATE
            # the goal is to turn off warnings introduced by SWIG, but leave enough enabled that actual issues with the input
            # program headers will get shown.
            -Wno-zero-as-null-pointer-constant
            -Wno-unused-macros
            -Wno-used-but-marked-unused
            -Wno-extra-semi-stmt
            -Wno-unused-parameter
            -Wno-shadow
            -Wno-suggest-override
            -Wno-deprecated-copy-with-user-provided-dtor
            -Wno-cast-qual
        )
        target_link_libraries(${SWIG_TARGET} PRIVATE ${TARGET})

        # Post-processing to work around a 16 year old swig bug. Sigh.
        # Note that this does nothing except copy the files: the interesting stuff is appended to this custom command
        # in the language-specific blocks below.
        add_custom_command(
            OUTPUT "${TAGFILE}"
            COMMAND cmake -E copy_directory ${SWIG_TMP}/${LANG} ${SWIG_OUT}/${LANG}
            COMMAND cmake -E touch "${TAGFILE}"
            DEPENDS ${SWIG_TARGET}
        )
        # Language-specific magic goes here.
        if (${LANG} STREQUAL python)
            # For Python bindings, we need Python libraries and stuff.
            find_package(Python COMPONENTS Development.Module REQUIRED)
            target_link_libraries(${SWIG_TARGET} PRIVATE Python::Module)

            # All python exceptions must inherit from BaseException, but SWIG fails to do this.
            add_custom_command(OUTPUT "${TAGFILE}" APPEND
                COMMAND sed -i"" -Ee "s|class Exception\\(object\\):|class Exception\\(BaseException\\):|g" ${SWIG_OUT}/${LANG}/${TARGET}.py
            )
        endif()

        add_custom_target(${SWIG_TARGET}_pp ALL DEPENDS ${TAGFILE})
    endforeach()
endfunction()
