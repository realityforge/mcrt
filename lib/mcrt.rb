require 'net/http'
require 'net/https'
require 'uri'
require 'json'

class MavenCentralPublishTool
  def self.buildr_release(project, profile_name, username, password)
    release_to_url = Buildr.repositories.release_to[:url]
    release_to_username = Buildr.repositories.release_to[:username]
    release_to_password = Buildr.repositories.release_to[:password]

    begin
      Buildr.repositories.release_to[:url] = 'https://oss.sonatype.org/service/local/staging/deploy/maven2'
      Buildr.repositories.release_to[:username] = username
      Buildr.repositories.release_to[:password] = password

      project.task(':upload').invoke

      r = MavenCentralPublishTool.new
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

  def get_staging_repositories(profile_name)
    result = get_request('https://oss.sonatype.org/service/local/staging/profile_repositories')
    result = JSON.parse(result)
    result['data'].select do |repo|
      repo['profileName'] == profile_name &&
        repo['userId'] == self.username &&
        repo['userAgent'] == self.user_agent &&
        repo['description'] == 'Implicitly created (auto staging).'
    end
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
      puts "Requesting promotion of staging repository #{profile_name}:#{candidate['repositoryId']}"
      begin
        promote_repository(candidate['repositoryId'], "Promoting repository for #{profile_name}")
      rescue Exception => e
        puts "#{e.class.name}: #{e.message}"
        puts e.backtrace.join("\n")
        raise 'Failed to promote repository. Please visit the website https://oss.sonatype.org/index.html#stagingRepositories and manually complete the release.'
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
