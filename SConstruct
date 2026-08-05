#!/usr/bin/env python
import os
import sys

env = Environment(ENV=os.environ)

opts = Variables()
opts.Add(PathVariable("godot_cpp_path", "Caminho para o godot-cpp", "godot-cpp"))
opts.Add("target", "Build target (template_debug, template_release)", "template_debug")
opts.Add("arch", "Architecture (x86_64, arm64, etc)", "x86_64")
opts.Update(env)

env = SConscript(env["godot_cpp_path"] + "/SConstruct")

# Adiciona diretório src para include
env.Append(CPPPATH=["src/"])

sources = Glob("src/*.cpp") + Glob("src/core/*.cpp") + Glob("src/net/*.cpp") + Glob("src/session/*.cpp") + Glob("src/adapters/*.cpp")

lib_name = "quantic_net"
env_platform = ARGUMENTS.get("platform", sys.platform)
if env_platform.startswith("win"):
    env_platform = "windows"
elif env_platform == "darwin":
    env_platform = "macos"

env_target = env["target"]
env_arch = env["arch"]

if env_platform == "windows":
    lib_path = "addons/quantic_net/bin/lib" + lib_name + "." + env_platform + "." + env_target + "." + env_arch + env["SHLIBSUFFIX"]
elif env_platform == "macos":
    lib_path = "addons/quantic_net/bin/lib" + lib_name + "." + env_platform + "." + env_target + ".universal" + env["SHLIBSUFFIX"]
else:
    lib_path = "addons/quantic_net/bin/lib" + lib_name + "." + env_platform + "." + env_target + "." + env_arch + env["SHLIBSUFFIX"]

env.Append(CXXFLAGS=["-std=c++17"])
if env_target in ["template_debug", "editor"]:
    env.Append(CXXFLAGS=["-O0", "-g"])
else:
    env.Append(CXXFLAGS=["-O2"])

library = env.SharedLibrary(
    target=lib_path,
    source=sources,
)

Default(library)
