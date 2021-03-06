require 'rubygems'
require 'rake'

begin
	require 'jeweler'
	Jeweler::Tasks.new do |gem|
		gem.name = "select"
		gem.summary = %Q{IO-event-handler based on select}
		gem.description = %Q{Select based event-handler for servers and sockets}
		gem.email = "ich@denkn.at"
		gem.license = 'LGPL-3.0'
		gem.homepage = "http://github.com/DenisKnauf/select"
		gem.authors = ["Denis Knauf"]
		gem.files = %w[README.md VERSION lib/**/*.rb test/**/*.rb]
		gem.require_paths = %w[lib]
	end
	Jeweler::GemcutterTasks.new
rescue LoadError
	puts "Jeweler (or a dependency) not available. Install it with: sudo gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
	test.libs << 'lib' << 'test' << 'ext'
	test.pattern = 'test/**/*_test.rb'
	test.verbose = true
end

begin
	require 'rcov/rcovtask'
	Rcov::RcovTask.new do |test|
		test.libs << 'test'
		test.pattern = 'test/**/*_test.rb'
		test.verbose = true
	end
rescue LoadError
	task :rcov do
		abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
	end
end

task :test => :check_dependencies

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
	if File.exist?('VERSION')
		version = File.read('VERSION')
	else
		version = ""
	end

	rdoc.rdoc_dir = 'rdoc'
	rdoc.title = "select #{version}"
	rdoc.rdoc_files.include('README*')
	rdoc.rdoc_files.include('lib/**/*.rb')
end
