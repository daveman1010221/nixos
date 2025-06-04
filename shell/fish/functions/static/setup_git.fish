function setup_git
    echo -n "Enter your Git user name: "
    read git_user
    echo -n "Enter your Git email: "
    read git_email
    echo -n "Do you want to configure Git credentials helper? (y/N): "
    read use_creds

    git config --global user.name "$git_user"
    git config --global user.email "$git_email"

    if test (string match -r '^[Yy]' -- $use_creds)
        echo -n "Enter your Git username (for HTTPS auth): "
        read gh_user
        echo -n "Enter your Git password or PAT: "
        read -l gh_pass

        git config --global credential.helper store

        echo "https://$gh_user:$gh_pass@github.com" > ~/.git-credentials
        chmod 600 ~/.git-credentials
    end

    echo "Git is configured. Welcome to 2009."
end
