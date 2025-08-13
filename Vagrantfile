Vagrant.configure("2") do |config|
    config.vm.box = "spox/ubuntu-arm"
    config.vm.box_version = "1.0.0"
  
    # Define common settings
    nodes = [
      {name: "wg1", ip: "192.168.56.11"},
      {name: "wg2", ip: "192.168.56.12"},
      {name: "wg3", ip: "192.168.56.13"}
    ]
  
    nodes.each do |node|
      config.vm.define node[:name] do |node_config|
        node_config.vm.hostname = node[:name]
        node_config.vm.network "private_network", ip: node[:ip]
  
        node_config.vm.provider "vmware_desktop" do |vmware|
          vmware.ssh_info_public = true
          vmware.gui = false
        end
      end
    end
  end
