function connect_dropbear --description "client-side helper for connecting to the dropbear server in the container"
    ssh-keygen -R [127.0.0.1]:2222
    ssh -p 2222 'djshepard@127.0.0.1' -o StrictHostKeyChecking=accept-new
end
