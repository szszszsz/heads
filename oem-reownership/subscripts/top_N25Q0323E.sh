#N25Q0323E
echo -e "Backuping N25Q032..3E top SPI flash into top.rom\n" && sudo flashrom -r ./top.rom --programmer ch341a_spi -c "N25Q032..3E" && echo -e "Verifying N25Q032..3E top SPI flash\n" && sudo flashrom -v ./top.rom --programmer ch341a_spi -c "N25Q032..3E" && echo -e "Flashing N25Q032..3E top SPI flash\n" && sudo flashrom -w  ./PrivacyBeastX230-QubesOS-Certified-ROMS/x230-flash-libremkey.rom  --programmer ch341a_spi -c "N25Q032..3E" 