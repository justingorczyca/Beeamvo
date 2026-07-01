#!/usr/bin/env ruby

require 'xcodeproj'

# Open the Xcode project
project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the Runner target
target = project.targets.find { |t| t.name == 'Runner' }

# Get the Runner group
runner_group = project.main_group.find_subpath('Runner', false)

# Add the Objective-C files
whisper_plugin_h = runner_group.new_file('WhisperPlugin.h')
whisper_plugin_m = runner_group.new_file('WhisperPlugin.m')

# Add the implementation file to the compile sources
target.source_build_phase.add_file_reference(whisper_plugin_m)

# Save the project
project.save

puts "Added WhisperPlugin.h and WhisperPlugin.m to the Runner target"
