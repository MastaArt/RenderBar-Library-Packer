/*
	Library Packer
	by MastaMan
	Installer file
	
	https://3dground.net/
*/

fn installLibraryPacker = (
	local currScript = getThisScriptFileName()	
	local pth = getFileNamePath currScript
	local scr = pth + "Library_Packer.ms"
	
	if (not doesFileExist scr) do return messageBox "Library_Packer.ms not found!\nPlease download script from GitHub and try again!" title: "Error!"
	
	n = "\n"
	ex = "macroScript RunLibraryPacker" + n
	ex += "category:\"[3DGROUND]\"" + n
	ex += "toolTip:\"LibraryPacker\"" + n
	ex += "buttontext:\"LibraryPacker\"" + n
	ex += "(" + n
	ex += "on execute do (" + n
	ex += "try(fileIn(@\"" + scr + "\")) catch(messageBox \"Script not found! Please reinstall Library_Packer.ms!\" title: \"Warning!\")" + n
	ex += ")" + n
	ex += ")" + n
	
	execute ex
	
	m = "Library Packer installed success!" + n
	m += "You can find it in [3DGROUND] category." + n + n
	m += "Please do not forgot to import fresh Render_Bar.prst" + n
	m += "for ModelPacker script!"
	
	messageBox m title: "Installed" beep: false
)


installLibraryPacker()