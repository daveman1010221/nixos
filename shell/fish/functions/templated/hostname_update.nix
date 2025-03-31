{ hostname, ... }:

''
function hostname_update --description="Update hostname to reflect current IP address."
    echo "This function needs updated for nixos."
    # This is a reasonably safe way to grab the currently configured network
    # device. This will currently only grab the current wifi adapter.
    #set m_if (ip -4 addr list | \
        #rg 'state\ UP' | \
        #rg -v 'br-' | \
        #cut -d ' ' -f 2 | \
        #string sub --end -1 | \
        #rg wl)

    # This is a reasonably safe way to grab the current IP address of the current network device.
    #set m_ip (ip -4 addr list | \
        #rg $m_if | \
        #rg 'dynamic' | \
        #string trim | \
        #cut -d ' ' -f 2 | \
        #rg -o '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])')

    #set NEW_HOSTNAME ${hostname}.$m_ip.nip.io

    # nip.io creates resolvable hostnames by embedding their IP in the hostname
    # and then resolving the hostname to that IP address.
    # doas hostnamectl set-hostname ${hostname}.$m_ip.nip.io
    #echo $NEW_HOSTNAME | \
        #doas tee /etc/hostname /proc/sys/kernel/hostname >/dev/null
end
''
