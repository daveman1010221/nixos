  unpackPhase
  cd linux-6.xx.xx/
  cp ../.config .
  cp ../MOK* linux-6.xx.xx/
  patchPhase
  make oldconfig
  kconfig nconfig
  khost
  kkernel
