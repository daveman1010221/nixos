{ user, name, email, smtpPass }:

''
# Check if .gitconfig exists for user ${user}
if [ ! -f /home/${user}/.gitconfig ]; then
  echo "Creating .gitconfig for ${user}"
  cat > /home/${user}/.gitconfig <<EOF
[user]
    email = ${email}
    name = ${name}
[sendemail]
    smtpencryption = tls
    smtpserverport = 587
    smtpuser = ${email}
    smtpserver = smtp.googlemail.com
    smtpPass = ${smtpPass}
[pull]
    rebase = false
[http]
    sslCAPath = /etc/ssl/certs/ca-certificates.crt
    sslVerify = true
    sslCAFile = /etc/ssl/certs/ca-certificates.crt
    sslCAInfo = /etc/ssl/certs/ca-certificates.crt
[init]
    defaultBranch = main
[core]
    pager = delta
    autocrlf = false

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    light = false
    side-by-side = true
    line-numbers = true
    theme = gruvbox-dark

[merge]
    conflictstyle = diff3

[diff]
    colorMoved = default
[filter "lfs"]
    clean = git-lfs clean -- %f
    smudge = git-lfs smudge -- %f
    process = git-lfs filter-process
    required = true
EOF

  chown ${user} /home/${user}/.gitconfig
  echo "********* Remember to create your ~/.git-credentials file with your token *********"
else
  echo ".gitconfig already exists for ${user}, skipping..."
fi
''
