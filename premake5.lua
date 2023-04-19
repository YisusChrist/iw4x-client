gitVersioningCommand = "git describe --tags --dirty --always"
gitCurrentBranchCommand = "git symbolic-ref -q --short HEAD"

-- Quote the given string input as a C string
function cstrquote(value)
	if value == nil then
		return "\"\""
	end
	result = value:gsub("\\", "\\\\")
	result = result:gsub("\"", "\\\"")
	result = result:gsub("\n", "\\n")
	result = result:gsub("\t", "\\t")
	result = result:gsub("\r", "\\r")
	result = result:gsub("\a", "\\a")
	result = result:gsub("\b", "\\b")
	result = "\"" .. result .. "\""
	return result
end

-- Converts tags in "vX.X.X" format to an array of numbers {X,X,X}.
-- In the case where the format does not work fall back to old {4,2,REVISION}.
function vertonumarr(value, vernumber)
	vernum = {}
	for num in string.gmatch(value, "%d+") do
		table.insert(vernum, tonumber(num))
	end
	if #vernum < 3 then
		return {4,2,tonumber(vernumber)}
	end
	return vernum
end

dependencies = {
	basePath = "./deps"
}

function dependencies.load()
	dir = path.join(dependencies.basePath, "premake/*.lua")
	deps = os.matchfiles(dir)

	for i, dep in pairs(deps) do
		dep = dep:gsub(".lua", "")
		require(dep)
	end
end

function dependencies.imports()
	for i, proj in pairs(dependencies) do
		if type(i) == 'number' then
			proj.import()
		end
	end
end

function dependencies.projects()
	for i, proj in pairs(dependencies) do
		if type(i) == 'number' then
			proj.project()
		end
	end
end

newoption {
	trigger = "copy-to",
	description = "Optional, copy the DLL to a custom folder after build, define the path here if wanted.",
	value = "PATH"
}

newoption {
	trigger = "copy-pdb",
	description = "Copy debug information for binaries as well to the path given via --copy-to."
}

newoption {
	trigger = "force-unit-tests",
	description = "Always compile unit tests."
}

newoption {
	trigger = "disable-binary-check",
	description = "Do not perform integrity checks on the exe."
}

newaction {
	trigger = "version",
	description = "Returns the version string for the current commit of the source code.",
	onWorkspace = function(wks)
		-- get current version via git
		local proc = assert(io.popen(gitVersioningCommand, "r"))
		local gitDescribeOutput = assert(proc:read('*a')):gsub("%s+", "")
		proc:close()
		local version = gitDescribeOutput

		proc = assert(io.popen(gitCurrentBranchCommand, "r"))
		local gitCurrentBranchOutput = assert(proc:read('*a')):gsub("%s+", "")
		local gitCurrentBranchSuccess = proc:close()
		if gitCurrentBranchSuccess then
			-- We got a branch name, check if it is a feature branch
			if gitCurrentBranchOutput ~= "develop" and gitCurrentBranchOutput ~= "master" then
				version = version .. "-" .. gitCurrentBranchOutput
			end
		end

		print(version)
		os.exit(0)
	end
}

newaction {
	trigger = "generate-buildinfo",
	description = "Sets up build information file like version.h.",
	onWorkspace = function(wks)
		-- get revision number via git
		local proc = assert(io.popen("git rev-list --count HEAD", "r"))
		local revNumber = assert(proc:read('*a')):gsub("%s+", "")

		-- get current version via git
		local proc = assert(io.popen(gitVersioningCommand, "r"))
		local gitDescribeOutput = assert(proc:read('*a')):gsub("%s+", "")
		proc:close()

		-- get whether this is a clean revision (no uncommitted changes)
		proc = assert(io.popen("git status --porcelain", "r"))
		local revDirty = (assert(proc:read('*a')) ~= "")
		if revDirty then revDirty = 1 else revDirty = 0 end
		proc:close()

		-- get current tag name
		proc = assert(io.popen("git describe --tags --abbrev=0"))
		local tagName = assert(proc:read('*l'))

		-- get old version number from version.hpp if any
		local oldVersion = "(none)"
		local oldVersionHeader = io.open(wks.location .. "/src/version.h", "r")
		if oldVersionHeader ~= nil then
			local oldVersionHeaderContent = assert(oldVersionHeader:read('*l'))
			while oldVersionHeaderContent do
				m = string.match(oldVersionHeaderContent, "#define GIT_DESCRIBE (.+)%s*$")
				if m ~= nil then
					oldVersion = m
				end

				oldVersionHeaderContent = oldVersionHeader:read('*l')
			end
		end

		-- generate version.hpp with a revision number if not equal
		gitDescribeOutputQuoted = cstrquote(gitDescribeOutput)
		if oldVersion ~= gitDescribeOutputQuoted then
			print ("Update " .. oldVersion .. " -> " .. gitDescribeOutputQuoted)
			local versionHeader = assert(io.open(wks.location .. "/src/version.h", "w"))
			versionHeader:write("/*\n")
			versionHeader:write(" * Automatically generated by premake5.\n")
			versionHeader:write(" * Do not touch!\n")
			versionHeader:write(" */\n")
			versionHeader:write("\n")
			versionHeader:write("#define GIT_DESCRIBE " .. gitDescribeOutputQuoted .. "\n")
			versionHeader:write("#define GIT_DIRTY " .. revDirty .. "\n")
			versionHeader:write("#define GIT_TAG " .. cstrquote(tagName) .. "\n")
			versionHeader:write("\n")
			versionHeader:write("// New revision definition. Will be used from now on\n")
			versionHeader:write("#define REVISION " .. revNumber .. "\n")
			versionHeader:write("\n")
			versionHeader:write("// Alias definitions\n")
			versionHeader:write("#define VERSION GIT_DESCRIBE\n")
			versionHeader:close()
			local versionHeader = assert(io.open(wks.location .. "/src/version.hpp", "w"))
			versionHeader:write("/*\n")
			versionHeader:write(" * Automatically generated by premake5.\n")
			versionHeader:write(" * Do not touch!\n")
			versionHeader:write(" *\n")
			versionHeader:write(" * This file exists for reasons of complying with our coding standards.\n")
			versionHeader:write(" *\n")
			versionHeader:write(" * The Resource Compiler will ignore any content from C++ header files if they're not from STDInclude.hpp.\n")
			versionHeader:write(" * That's the reason why we now place all version info in version.h instead.\n")
			versionHeader:write(" */\n")
			versionHeader:write("\n")
			versionHeader:write("#include \".\\version.h\"\n")
			versionHeader:close()
		end
	end
}

dependencies.load()

workspace "iw4x"
	startproject "iw4x"
	location "./build"
	objdir "%{wks.location}/obj"
	targetdir "%{wks.location}/bin/%{cfg.platform}/%{cfg.buildcfg}"

	configurations {"Debug", "Release"}

	language "C++"
	cppdialect "C++20"

	architecture "x86"
	platforms "Win32"

	systemversion "latest"
	symbols "On"
	staticruntime "On"
	editandcontinue "Off"
	warnings "Extra"
	characterset "ASCII"

	flags {"NoIncrementalLink", "NoMinimalRebuild", "MultiProcessorCompile", "No64BitChecks"}

	filter "platforms:Win*"
		defines {"_WINDOWS", "WIN32"}
	filter {}

	filter "configurations:Release"
		optimize "Size"
		buildoptions {"/GL"}
		linkoptions {"/IGNORE:4702", "/LTCG"}
		defines {"NDEBUG"}
		flags {"FatalCompileWarnings", "FatalLinkWarnings"}

		if not _OPTIONS["force-unit-tests"] then
			rtti ("Off")
		end
	filter {}

	filter "configurations:Debug"
		optimize "Debug"
		defines {"DEBUG", "_DEBUG"}
	filter {}

	project "iw4x"
		kind "SharedLib"
		language "C++"
		files {
			"./src/**.rc",
			"./src/**.hpp",
			"./src/**.cpp",
		}
		includedirs {
			"%{prj.location}/src",
			"./src",
			"./lib/include",
		}
		resincludedirs {
			"$(ProjectDir)src" -- fix for VS IDE
		}

		-- Debug flags
		if _OPTIONS["force-unit-tests"] then
			defines {"FORCE_UNIT_TESTS"}
		end
		if _OPTIONS["disable-binary-check"] then
			defines {"DISABLE_BINARY_CHECK"}
		end

		-- Pre-compiled header
		pchheader "STDInclude.hpp" -- must be exactly same as used in #include directives
		pchsource "src/STDInclude.cpp" -- real path

		dependencies.imports()

		-- Pre-build
		prebuildcommands
		{
			"pushd %{_MAIN_SCRIPT_DIR}",
			"tools\\premake5 generate-buildinfo",
			"popd",
		}

		-- Post-build
		if _OPTIONS["copy-to"] then
			saneCopyToPath = string.gsub(_OPTIONS["copy-to"] .. "\\", "\\\\", "\\")
			postbuildcommands {
				"if not exist \"" .. saneCopyToPath .. "\" mkdir \"" .. saneCopyToPath .. "\"",
			}

			if _OPTIONS["copy-pdb"] then
				postbuildcommands {
					"copy /y \"$(TargetDir)*.pdb\" \"" .. saneCopyToPath .. "\"",
				}
			end

			-- This has to be the last one, as otherwise VisualStudio will succeed building even if copying fails
			postbuildcommands {
				"copy /y \"$(TargetDir)*.dll\" \"" .. saneCopyToPath .. "\"",
			}
		end


group "External Dependencies"
dependencies.projects()

rule "ProtobufCompiler"
	display "Protobuf compiler"
	location "./build"
	fileExtension ".proto"
	buildmessage "Compiling %(Identity) with protoc..."
	buildcommands {
		'@echo off',
		'path "$(SolutionDir)\\..\\tools"',
		'if not exist "$(ProjectDir)\\src\\proto" mkdir "$(ProjectDir)\\src\\proto"',
		'protoc --error_format=msvs -I=%(RelativeDir) --cpp_out=src\\proto %(Identity)',
	}
	buildoutputs {
		'$(ProjectDir)\\src\\proto\\%(Filename).pb.cc',
		'$(ProjectDir)\\src\\proto\\%(Filename).pb.h',
	}
