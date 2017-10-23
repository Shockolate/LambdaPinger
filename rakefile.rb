require 'aws-sdk'
Aws.use_bundled_cert!
require 'rake'
require 'rake/clean'
require 'fileutils'
require 'lambda_wrap'
require 'yaml'
require 'zip'
require 'securerandom'
require 'active_support/core_ext/hash'

STDOUT.sync = true
STDERR.sync = true

PWD = File.dirname(__FILE__)
SRC_DIR = File.join(PWD, 'src')
PACKAGE_DIR = File.join(PWD, 'package')
CONFIG_DIR = File.join(PWD, 'config')
MODULES_DIR = File.join(PWD, 'node_modules')

CLEAN.include(PACKAGE_DIR)
CLEAN.include(File.join(PWD, 'reports'))
CLOBBER.include(File.join(PWD, 'node_modules'))

# Developer tasks
desc 'Lints, unit tests, and builds the package directory.'
task :build => [:parse_config, :retrieve, :lint, :unit_test, :package]

desc 'Runs unit and integration tests.'
task :test => [:retrieve, :lint, :unit_test, :integration_test]

# Build Runner Targets
task :merge_job => [:clean, :parse_config, :retrieve, :lint, :unit_test_report, :coverage, :package, :deploy_production]
task :pull_request_job => [:clean, :parse_config, :retrieve, :lint, :unit_test_report, :coverage, :package, :deploy_test, :integration_test, :e2e_test]

task :deploy_production => [:parse_config, :build] do
  deploy(:production)
  #upload_swagger_file
end

task :deploy_test => [:parse_config, :build] do
  deploy(:test)
end

task :deploy_environment, [:environment, :verbosity] => [:build] do |t, args|
  raise 'Parameter environment needs to be set' if args[:environment].nil?
  raise 'Parameter verbosity needs to be set' if args[:verbosity].nil?
  API.deploy(LambdaWrap::Environment.new(args[:environment], { 'verbosity' => args[:verbosity] }))
end

desc 'Don\'t.'
task :teardown_production => [:parse_config] do
  teardown(:production)
end

desc 'If you want.'
task :teardown_test => [:parse_config] do
  teardown(:test)
end

desc 'tears down an environment - Removes Lambda Aliases and Deletes API Gateway Stage.'
task :teardown_environment, [:environment] => [:parse_config] do |t, args|
  # validate input parameters
  env = args[:environment]
  raise 'Parameter environment needs to be set' if env.nil?
  API.teardown(LambdaWrap::Environment.new(name: args[:environment]))
end

# Workflow tasks
desc 'Retrieves external dependencies. Calls "npm install"'
task :retrieve do
  puts 'Retrieving node modules...'
  t1 = Time.now
  cmd = 'npm install'
  raise 'Node Modules not installed.' if !system(cmd)
  t2 = Time.now
  puts "Retrieved node modules. #{t2 - t1}"
end

desc 'Parses and Lints src and test directories. Calls "npm run lint"'
task :lint do
  cmd = 'npm run lint'
  raise 'Error linting.' if !system(cmd)
end

desc 'Runs code coverage on unit tests'
task :coverage do
  cmd = "npm run cover"
  raise 'Error running code coverage.' if !system(cmd)
end

desc 'Runs Unit tests located in the test/unit directory.
  Calls "npm run unit_test"'
task :unit_test do
  cmd = "npm run unit_test"
  raise 'Error running unit tests.' if !system(cmd)
end

desc 'Runs Unit tests and located in the test/unit directory.
  Outputs results to test-reports.xml. Calls "npm run unit_test_report"'
task :unit_test_report do
  cmd = "npm run unit_test_report"
  raise 'Error running unit tests.' if !system(cmd)
end

desc 'Runs Integration tests located in the test/integration directory.
  Calls "npm run integration_test"'
task :integration_test do
  cmd = "npm run integration_test"
  raise 'Error running integration tests.' if !system(cmd)
end

desc 'Runs End-to-end tests located in the test/e2e directory.
  Calls "npm run e2e_test"'
task :e2e_test do
  cmd = "npm run e2e_test"
  raise 'Error running End-To-End tests.' if !system(cmd)
end

desc 'Creates a package for deployment.'
task :package => [:clean, :parse_config, :retrieve] do
  package()
end

task :parse_config do
  puts 'Parsing config...'
  CONFIGURATION = YAML::load_file(File.join(CONFIG_DIR, 'config.yaml')).deep_symbolize_keys
  API = LambdaWrap::API.new()

  ENVIRONMENTS = {}

  CONFIGURATION[:environments].each do |e|
    ENVIRONMENTS[e[:name].to_sym] = LambdaWrap::Environment.new(e[:name], e[:variables], e[:description])
  end

  API.add_lambda(
    CONFIGURATION[:lambdas].map do |lambda_config|
      lambda_config[:path_to_zip_file] = File.join(PACKAGE_DIR, 'deployment_package.zip')
      LambdaWrap::Lambda.new(lambda_config)
    end
  )

  #API.add_api_gateway(
  #  LambdaWrap::ApiGateway.new(path_to_swagger_file: File.join(CONFIG_DIR, 'swagger.yaml'))
  #)
  puts 'parsed. '
end

def upload_swagger_file()
  cleaned_swagger = clean_swagger(YAML::load_file(File.join(CONFIG_DIR, 'swagger.yaml')))
  puts "uploading Swagger File..."
  s3 = Aws::S3::Client.new()
  s3.put_object(acl: 'public-read', body: cleaned_swagger, bucket: CONFIGURATION[:s3][:swagger][:bucket],
    key: CONFIGURATION[:s3][:swagger][:key])
  puts "Swagger File uploaded."
end

def package()
  puts 'Creating the deployment package...'
  t1 = Time.now

  puts 'Zipping source and modules...'

  # move all dependencies to a temporary folder
  temp_dir = File.join(PWD, SecureRandom.uuid)
  FileUtils.move(MODULES_DIR, temp_dir)

  download_production_dependencies

  zip_modules_and_source_files

  # delete the production dependencies folder
  FileUtils.rm_rf(MODULES_DIR, verbose: true)
  FileUtils.move(temp_dir, MODULES_DIR)

  puts 'Zipped source and modules.'

  unless CONFIGURATION[:s3].nil?
    unless CONFIGURATION[:s3][:secrets].nil?
      unless CONFIGURATION[:s3][:secrets][:bucket].nil? && CONFIGURATION[:s3][:secrets][:key].nil?
        download_secrets
        secrets = extract_secrets
        add_secrets_to_package(secrets)
        cleanup_secrets(secrets)
      end
    end
  end

  t2 = Time.now
  puts
  puts "Successfully created the deployment package! #{t2 - t1}"
end

def clean_swagger(swagger_yaml)
  puts "cleaning Swagger File..."
  swagger_yaml["paths"].each do |pathKey, pathValue|
    swagger_yaml["paths"][pathKey].each do |methodKey, methodValue|
      swagger_yaml["paths"][pathKey][methodKey] = methodValue.reject{|key, value| key == "x-amazon-apigateway-integration"}
    end
  end
  swagger_yaml["paths"] = swagger_yaml["paths"].reject{|key, value| key == "/swagger"}
  puts "cleaned."
  return YAML::dump(swagger_yaml).sub(/^(---\n)/, "")
end

def download_production_dependencies
  cmd = 'npm install --production'
  raise 'Production Node Modules not installed.' if !system(cmd)
end

def filter_entries(directory)
  Dir.entries(directory) - %w[. ..]
end

def zip_modules_and_source_files
  FileUtils.mkdir(PACKAGE_DIR, verbose: true)
  Zip::File.open(File.join(PACKAGE_DIR, 'deployment_package.zip'), Zip::File::CREATE) do |io|
    write_entries(filter_entries(SRC_DIR), '', io, SRC_DIR) # Zip Source Files
    write_entries(filter_entries(MODULES_DIR).map { |e| "node_modules/#{e}" }, '', io, PWD) # Zip Node Modules
  end
end

def write_entries(entries, path, io, input_directory)
  entries.each do |e|
    zip_file_path = path == '' ? e : File.join(path, e)
    disk_file_path = File.join(input_directory, zip_file_path)
    puts "Deflating #{disk_file_path}"

    if File.directory? disk_file_path
      recursively_deflate_directory(disk_file_path, io, zip_file_path, input_directory)
    else
      put_into_archive(disk_file_path, io, zip_file_path)
    end
  end
end

def recursively_deflate_directory(disk_file_path, io, zip_file_path, input_directory)
  io.mkdir zip_file_path
  write_entries(filter_entries(disk_file_path), zip_file_path, io, input_directory)
end

def put_into_archive(disk_file_path, io, zip_file_path)
  io.add(zip_file_path, disk_file_path)
end

def download_secrets
  puts 'Downloading secrets zip...'
  s3 = Aws::S3::Client.new()
  s3.get_object(
    response_target: PACKAGE_DIR + '/' + CONFIGURATION[:s3][:secrets][:key],
    bucket: CONFIGURATION[:s3][:secrets][:bucket],
    key: CONFIGURATION[:s3][:secrets][:key]
  )
  puts 'Secrets downloaded. '
end

def extract_secrets
  secrets_entries = Array.new
  puts 'Extracting Secrets...'
  Zip::File.open(PACKAGE_DIR + '/' + CONFIGURATION[:s3][:secrets][:key]) do |secrets_zip_file|
    secrets_zip_file.each do |entry|
      secrets_entries.push(entry.name)
      entry.extract(File.join(PACKAGE_DIR, entry.name))
    end
  end
  puts 'Secrets Extracted. '
  secrets_entries
end

def add_secrets_to_package(secrets)
  puts 'Adding secrets to package...'
  Zip::File.open(File.join(PACKAGE_DIR, 'deployment_package.zip'), Zip::File::CREATE) do |zipfile|
    secrets.each do |entry|
      zipfile.add(entry, File.join(PACKAGE_DIR, entry))
    end
  end
  puts 'Added secrets to package. '
end

def cleanup_secrets(secrets)
  puts 'Cleaning up secrets...'
  secrets << CONFIGURATION[:s3][:secrets][:key]
  FileUtils.rm(secrets.map { |secret| File.join(PACKAGE_DIR, secret) }, verbose: true)
  puts 'Cleaned up secrets.'
end

def deploy(environment_symbol)
  raise ArgumentError 'Must pass an environment symbol!' unless environment_symbol.is_a?(Symbol)
  API.deploy(ENVIRONMENTS[environment_symbol])
end

def teardown(environment_symbol)
  raise ArgumentError 'Must pass an environment symbol!' unless environment_symbol.is_a?(Symbol)
  API.deploy(ENVIRONMENTS[environment_symbol])
end
