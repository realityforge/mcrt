require 'net/http'
require 'net/https'
require 'uri'
require 'json'

class MavenCentralReleaseTool
  class << self
    def define_publish_tasks(options = {})
      candidate_branches = options[:branches] || %w(master)
      desc 'Publish release on maven central'
      task 'mcrt:publish' do
        project = options[:project] || Buildr.projects[0].root_project
        profile_name = options[:profile_name] || (raise ':profile_name not specified when defining tasks')
        username = options[:username] || (raise ':username name not specified when defining tasks')
        password = options[:password] || ENV['MAVEN_CENTRAL_PASSWORD'] || (raise "Unable to locate environment variable with name 'MAVEN_CENTRAL_PASSWORD'")
        MavenCentralReleaseTool.buildr_release(project, profile_name, username, password)
      end

      desc 'Publish release to maven central iff current HEAD is a tag'
      task 'mcrt:publish_if_tagged' do
        tag = MavenCentralReleaseTool.get_head_tag_if_any
        if tag.nil?
          puts 'Current HEAD is not a tag. Skipping publish step.'
        else
          puts "Current HEAD is a tag: #{tag}"
          if MavenCentralReleaseTool.is_tag_on_candidate_branches?(tag, candidate_branches)
            task('mcrt:publish').invoke
          end
        end
      end
    end

    def get_head_tag_if_any
      version = `git describe --exact-match --tags 2>&1`
      if 0 == $?.exitstatus && version =~ /^v[0-9]/ && (ENV['TRAVIS_BUILD_ID'].nil? || ENV['TRAVIS_TAG'].to_s != '')
        version.strip
      else
        nil
      end
    end

    def is_tag_on_branch?(tag, branch)
      output = `git tag --merged #{branch} 2>&1`
      tags = output.split
      tags.include?(tag)
    end

    def is_tag_on_candidate_branches?(tag, branches)
      sh 'git fetch origin'
      branches.each do |branch|
        if is_tag_on_branch?(tag, branch)
          puts "Tag #{tag} is on branch: #{branch}"
          return true
        elsif is_tag_on_branch?(tag, "origin/#{branch}")
          puts "Tag #{tag} is on branch: origin/#{branch}"
          return true
        else
          puts "Tag #{tag} is not on branches: #{branch} or origin/#{branch}"
        end
      end
      false
    end

    def buildr_release(project, profile_name, username, password)
      release_to_url = Buildr.repositories.release_to[:url]
      release_to_username = Buildr.repositories.release_to[:username]
      release_to_password = Buildr.repositories.release_to[:password]

      begin
        Buildr.repositories.release_to[:url] = 'https://oss.sonatype.org/service/local/staging/deploy/maven2'
        Buildr.repositories.release_to[:username] = username
        Buildr.repositories.release_to[:password] = password

        project.task(':upload').invoke

        r = MavenCentralReleaseTool.new
        r.username = username
        r.password = password
        r.user_agent = "Buildr-#{Buildr::VERSION}"
        r.release_sole_auto_staging(profile_name)
      ensure
        Buildr.repositories.release_to[:url] = release_to_url
        Buildr.repositories.release_to[:username] = release_to_username
        Buildr.repositories.release_to[:password] = release_to_password
      end
    end
  end

  attr_writer :username

  def username
    @username || (raise 'Username not yet specified')
  end

  attr_writer :password

  def password
    @password || (raise 'Password not yet specified')
  end

  attr_writer :user_agent

  def user_agent
    @user_agent || "Ruby-#{RUBY_VERSION}"
  end

  def get_staging_repositories(profile_name, ignore_transitioning_repositories = true)
    result = get_request('https://oss.sonatype.org/service/local/staging/profile_repositories')
    result = JSON.parse(result)
    result['data'].select do |repo|
      repo['profileName'] == profile_name &&
        repo['userId'] == self.username &&
        repo['userAgent'] == self.user_agent &&
        (!ignore_transitioning_repositories || !repo['transitioning']) &&
        get_my_ip_addresses.any? {|a| a == repo['ipAddress']}
    end
  end

  def get_my_ip_addresses
    addresses = Socket.ip_address_list.collect {|a| a.ip_address.to_s}
    begin
      addresses << Net::HTTP.get(URI('http://www.myexternalip.com/raw')).strip
    rescue Error
      # ignored
    end
    addresses
  end

  def close_repository(repository_id, description)
    post_request('https://oss.sonatype.org/service/local/staging/bulk/close',
                 JSON.pretty_generate('data' => { 'description' => description, 'stagedRepositoryIds' => [repository_id] }))
  end

  def promote_repository(repository_id, description)
    post_request('https://oss.sonatype.org/service/local/staging/bulk/promote',
                 JSON.pretty_generate('data' => { 'autoDropAfterRelease' => true,
                                                  'description' => description,
                                                  'stagedRepositoryIds' => [repository_id] }))
  end

  def drop_repository(repository_id, description)
    post_request('https://oss.sonatype.org/service/local/staging/bulk/drop',
                 JSON.pretty_generate('data' => { 'description' => description, 'stagedRepositoryIds' => [repository_id] }))
  end

  def release_sole_auto_staging(profile_name)
    candidates = get_staging_repositories(profile_name)
    if candidates.empty?
      raise 'Release process unable to find any staging repositories.'
    elsif 1 != candidates.size
      raise 'Release process found multiple staging repositories that could be the release just uploaded. Please visit the website https://oss.sonatype.org/index.html#stagingRepositories and manually complete the release.'
    else
      candidate = candidates[0]
      puts "Requesting close of staging repository #{profile_name}:#{candidate['repositoryId']}"
      begin
        close_repository(candidate['repositoryId'], "Closing repository for #{profile_name}")
      rescue Exception => e
        puts "#{e.class.name}: #{e.message}"
        puts e.backtrace.join("\n")
        raise 'Failed to close repository. It is likely that the release does not conform to Maven Central release requirements. Please visit the website https://oss.sonatype.org/index.html#stagingRepositories and manually complete the release.'
      end
      while get_staging_repositories(profile_name).size == 0
        puts 'Waiting for repository to close...'
        sleep 1
      end
      puts "Requesting promotion of staging repository #{profile_name}:#{candidate['repositoryId']}"
      begin
        promote_repository(candidate['repositoryId'], "Promoting repository for #{profile_name}")
      rescue Exception => e
        puts "#{e.class.name}: #{e.message}"
        puts e.backtrace.join("\n")
        raise 'Failed to promote repository. Please visit the website https://oss.sonatype.org/index.html#stagingRepositories and manually complete the release.'
      end
      repositories = get_staging_repositories(profile_name, false)
      while repositories.size == 1
        puts 'Waiting for repository to be promoted...'
        sleep 1
        if repositories[0]['notifications'] != 0
          raise 'Failed to promote repository. Please visit the website https://oss.sonatype.org/index.html#stagingRepositories and manually complete the release.'
        end
        repositories = get_staging_repositories(profile_name, false)
      end
    end
  end

  private

  def create_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http
  end

  def setup_standard_request(request)
    request['Accept'] = 'application/json,application/vnd.siesta-error-v1+json,application/vnd.siesta-validation-errors-v1+json'
    request.basic_auth(self.username, self.password)
    request.add_field('User-Agent', self.user_agent)
  end

  def get_request(url)
    uri = URI.parse(url)
    request = Net::HTTP::Get.new(uri.request_uri)
    setup_standard_request(request)
    create_http(uri).request(request).body
  end

  def post_request(url, content)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri.request_uri)
    setup_standard_request(request)
    request.add_field('Content-Type', 'application/json')
    request.body = content
    create_http(uri).request(request).body
  end
end
