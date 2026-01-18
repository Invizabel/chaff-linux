* Chaff Linux is a Linux Distro that specializes in Secure Data Destruction using Shred and Chaff (PyPi).
* You will need Debian or a Debian based distro.
* chmod +x chaff_linux.sh && sudo ./chaff_linux.sh
* In-Place: Navigate to the drive you want using the cd command and enter Chaff.
* Entire Drive: Use the lsblk command to find the drive. Then shred -v /dev/<my_drive_here>
