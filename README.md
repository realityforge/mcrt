# Maven Central Release Tool

[![Build Status](https://secure.travis-ci.org/realityforge/mcrt.png?branch=master)](http://travis-ci.org/realityforge/mcrt)

This is very simply tool that allows you to close, promote and drop and staging repository in Maven Central.
The library assumes some other tool will upload the artifacts to the staging repository. This tool can then
be invoked to close, promote and drop the repository as required.

It has some very basic integration with [Buildr](http://buildr.apache.org) that allows you to close and promote
in one step. You need to supply the profile name (the name under which upload occurs which is usually reverse DNS
for a domain such as "org.realityforge") and user credential code to perform upload.

A snippet that is used in several buildr projects is:

```ruby
desc 'Publish release on maven central'
task 'publish_to_maven_central' do
  project = Buildr.projects[0].root_project
  username = ENV['MAVEN_CENTRAL_USERNAME'] || (raise "Unable to locate environment variable with name 'MAVEN_CENTRAL_USERNAME'")
  password = ENV['MAVEN_CENTRAL_PASSWORD'] || (raise "Unable to locate environment variable with name 'MAVEN_CENTRAL_PASSWORD'")
  MavenCentralPublishTool.buildr_release(project, 'org.realityforge', username, password)
end
```
