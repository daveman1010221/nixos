{
  services.resticUsbBackup = {
    enable = true;
    mountPoint = "/run/media/djshepard/Backups-New";
    repoSubdir = "whitey";
    user = "djshepard";
    insecureNoPassword = true;
  };
}
