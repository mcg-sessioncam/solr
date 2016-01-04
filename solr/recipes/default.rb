#
# Cookbook Name:: solr
# Recipe:: default
#
# Copyright 2013, David Radcliffe
#

if node['solr']['install_java']
  include_recipe 'apt'
  include_recipe 'java'
end

src_filename = ::File.basename(node['solr']['url'])
src_filepath = "#{Chef::Config['file_cache_path']}/#{src_filename}"
extract_path = "#{node['solr']['dir']}"
# extract_path = "#{node['solr']['dir']}-#{node['solr']['version']}"
solr_path = "#{extract_path}/#{node['solr']['version'].split('.')[0].to_i < 5 ? 'example' : 'server'}"

remote_file src_filepath do
  source node['solr']['url']
  action :create_if_missing
end

bash 'unpack_solr' do
  cwd ::File.dirname(src_filepath)
  code <<-EOH
   if [[ ! -d #{extract_path} ]]; then
    tar xzf #{src_filepath} solr-#{node['solr']['version']}/bin/install_solr_service.sh --strip-components 2
    #{Chef::Config['file_cache_path']}/install_solr_service.sh #{src_filepath}
    chown -R #{node['solr']['user']}:#{node['solr']['group']} #{extract_path}
    
   fi
  EOH
  not_if { ::File.exist?(extract_path) }
end

directory node['solr']['data_dir'] do
  owner node['solr']['user']
  group node['solr']['group']
  recursive true
  action :create
end

directory node['solr']['tlog'] do
  owner node['solr']['user']
  group node['solr']['group']
  recursive true
  action :create
end

#template '/var/lib/solr.start' do
#  source 'solr.start.erb'
#  owner 'root'
#  group 'root'
#  mode '0755'
#  variables(
#    :solr_dir => solr_path,
#    :solr_home => node['solr']['data_dir'],
#    :port => node['solr']['port'],
#    :pid_file => node['solr']['pid_file'],
#    :log_file => node['solr']['log_file'],
#    :java_options => node['solr']['java_options']
#  )
#end

template '/var/solr/solr.in.sh' do
  source 'solr.in.sh.erb'
  owner 'root'
  group 'root'
  mode '0755'
end

#template '/etc/init.d/solr' do
#  source platform_family?('debian') ? 'initd.debian.erb' : 'initd.erb'
 # owner 'root'
#  group 'root'
 # mode '0755'
  #variables(
   # :solr_dir => solr_path,
    #:solr_home => node['solr']['data_dir'],
    #:port => node['solr']['port'],
    #:pid_file => node['solr']['pid_file'],
    #:log_file => node['solr']['log_file'],
    #:user => node['solr']['user'],
    #:java_options => node['solr']['java_options']
  #)
#end

service 'solr' do
  supports :restart => true, :status => true
  action [:enable, :start]
end
