/*  
[INFO] 
NAME = RenderBar Library Packer
VERSION = 1.3.4
AUTHOR = Dev: MastaMan
THANKS = Author: Kenji
DEV = https://3dground.net
HELP = 
CLIENT = Kenji

[ABOUT]
Automate packing models for RenderBar 3D Library =

[1.0.0]
* Initial release =

[1.1.0]
+ Added: Installer=
+ Added: Separate layer for lights=
+ Added: Included preset Render_Bar.prst in delivery=
* Changed: Info in rollout About=
- BugFix: Not reload list categories when change new folder=

[1.1.1]
- BugFix: Remove mock=

[1.1.2]
* Changed: Last Changes=

[1.1.3]
+ Added: Hints when typing Model Name=
+ Added: GBuffer in nested layers names=
* Changed: Created new group Model Name and moved form=

[1.2.0]
+ Added: Workflows=
* Changed: UI=
* Changed: More improvements=

[1.2.1]
+ Added: Button Clear=

[1.2.2]
* Test: Updater=

[1.2.5]
+ Added: Preview functionality=
+ Added: Clear functionality=
+ Added: Apply functionality=
- BugFix: Small fixes=

[1.2.6]
+ Added: Manual Rename functinality=
+ Added: Support new preset RENDER_BAR_NORENAME=
- BugFix: Material logic for Plants workflow=
- BugFix: Not clear image after pack=

[1.2.7]
- BugFix: Replace spact to undescrore=

[1.2.8]
- BugFix: Green indicators after pack=

[1.2.9]
- BugFix: Unhandled exception 'cbx... in undefined'=

[1.3.0]
- BugFix: Can't process instances in MultiMaterial for prepare MultiMap + ColorCorrect=

[1.3.1]
+ Added: Functionality for add cat ids to Model Name=

[1.3.2]
* Changed: Link to repository=

[1.3.3]
- Removed: Logic for move objects to layers=

[1.3.4]
+ Added: Functionality for choose Corona Converter script=
+ Added: Button Convert to VRay=
+ Added: Support VRay=
+ Added: 5 level of category=

[SCRIPT]
*/


global IS_DEBUG_MODE = true

try(closeRolloutFloater floaterLibraryPacker) catch()
global floaterLibraryPacker = newRolloutFloater "Library Packer" 400 930


/* GLOBALS */

global MODEL_PACKER_PRESET = "RENDER_BAR"
global MODEL_PACKER_PRESET_NORENAME = "RENDER_BAR_NORENAME"

global scriptModelpacker = (getDir #temp) + @"\ModelPacker\ModelPacker.mse"

global scriptRelinkBitmaps = (getDir #userScripts) + @"\Relink Bitmaps\Relink Bitmaps.mse"
global scriptPruneScene = (getDir #temp) + @"\PruneScene\PruneScene.mse"
global scriptStockModelFixer = (getDir #temp) + @"\StockModelFixer\StockModelFixer.mse"
global scriptAlbedo = (getDir #userScripts) + @"\OS3D\OneClickAlbedo2.mse"
global scriptConvertToVRay = (getDir #userMacros) + @"\_3DGROUND_-RunCoronaToVrayConverter.mcr"

global goodChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890&$%#()!_-+ " 
global ignoreDirsPtrn = #("_*", "maps", "Maps")
global previewModelPath = ""
global colorHiglightItem = color 166 37 23

global texturePrefix = "[!]"

global isCategorySelected = false
global flowId = 1


global _rLibraryPacker
global _rStep1
global _rStepPlants

/* FUNCTIONS */

struct '@' (
	currScript = getThisScriptFileName(),
	name = getFilenameFile currScript,
	pth = getFileNamePath currScript,
	ini = pth +  sysinfo.username + "@" + sysinfo.computername + ".ini",
	--ini = (getThisScriptFileName()) + ".ini",
	sec = name,
	fn add k v = (
		setIniSetting this.ini this.sec k (v as string)
	),
	fn get k type: #string = (
		v = getIniSetting this.ini this.sec k
		
		case type of (
			#bool_true: return if (v == "true") then true else false
			#bool_false: return if (v == "false") then false else true
			#int: return try (v as integer) catch(0)
		)
		
		return v
	),
	fn trim s tag: " " = (
		s as string
		return (trimLeft (trimRight s tag) tag)
	)
)

global '*' = '@'()

fn freezeUi = (
    source = ""
    source += "using System;\n"
    source += "using System.Runtime.InteropServices;\n"
    source += "class WindowsGhosting\n"
    source += "{\n"
    source += " [DllImport(\"user32.dll\")]\n"
    source += " public static extern void DisableProcessWindowsGhosting();\n"
    source += "}\n"
  
    csharpProvider = dotnetobject "Microsoft.CSharp.CSharpCodeProvider"
    compilerParams = dotnetobject "System.CodeDom.Compiler.CompilerParameters"
  
    compilerParams.GenerateInMemory = on
    compilerResults = csharpProvider.CompileAssemblyFromSource compilerParams #(source)
  
    assembly = compilerResults.CompiledAssembly
    windowsGhosting = assembly.CreateInstance "WindowsGhosting"
    windowsGhosting.DisableProcessWindowsGhosting()
)

fn boost = if (((maxVersion())[1] / 1000) >= 13) do windows.processPostedMessages() 

fn getRender = (
	r = renderers.current as string

	if matchpattern r pattern:"*Corona*" do return #Corona
	if matchpattern r pattern:"*V_Ray*" do return #VRay
	if matchpattern r pattern:"*Default_Scanline*" do return #Scanline
	return #unknown
)

fn isValidRender = (
	case getRender() of (
		#Corona: return true
		#VRay: return true
		default: return false
	)
)

fn isCoronaInstalled =  (
	for i in RendererClass.classes where MatchPattern (i as string) pattern: "*Corona*" do return true
	return false
)


fn isValidText t = (
    c = for i in 1 to t.count where findString goodChars t[i] == undefined collect t[i]

    if(c.count > 0) do (
        c = makeUniqueArray c
        p1 = "Please type correct Model Name!"
        p2 = "\nWrong characters"
        m = p1 + "\n" + p2 + ": "
        for i in c do m += " \"" + i + "\", "

        return trimRight m ", "
    )
    
    return true
)

fn getMatById m id = (
	mm = m.materialList
	i = findItem (m.materialIDList) id	
	if (i == 0) do return undefined
	
	return mm[i]
)

fn formatString s v: #() tag: "$" urlEncode: false = (
	for i in 1 to v.count  do (
		t = v[i] as string
		s = substituteString s (tag + i as string) (t)
	)
	
	return s
)

/* ROLLOUTS */

rollout _rAboutLP "About" category: 999 (
    label lblName ""
    label lblVer "" 
    
    label lblAuthor ""
    label lblThanks "" height: 30
    hyperlink lblCopy ""  align: #center
    
	timer tmrRestart "" active: false interval: 300
	
	fn downloadFile url dl = (
		deleteFile dl
		w = dotNetObject "System.Net.WebClient"			
		try(
			spm = dotNetClass "System.Net.ServicePointManager"
			spm.SecurityProtocol = spm.SecurityProtocol.TLS12				
			w.DownloadFile (url + "?time=" + timestamp() as string) dl				
		) catch(
			return false
		)
		
		return true
	)
	
	fn bgUpdate = (
		url = "https://github.com/MastaArt/RenderBar-Library-Packer/raw/main/Library_Packer.ms"
		this = getThisScriptFileName()
		dl = this + ".tmp"
		r = downloadFile url dl
		if(not r or not doesFileExist dl) do return print "Can't download updates!"
		vn = getIniSetting dl "INFO" "VERSION"
		vo = getIniSetting this "INFO" "VERSION"
		
		if(vn > vo) do (
			deleteFile this
			renameFile dl this
			
			tmrRestart.active = true
		)
		
		deleteFile dl
	)
	
    fn getScriptInfo s releaseInfo: "" =  (
        if (releaseInfo != "") do
        (
            r = getINISetting s releaseInfo
            return r
        )

        v = getINISetting s "INFO" "VERSION"
        a = getINISetting s "INFO" "AUTHOR"
        t = getINISetting s "INFO" "THANKS"
        n = getINISetting s "INFO" "NAME"
        o = getINISetting s "ABOUT"
        c = getINISetting s "INFO" "DEV"
        h = getINISetting s "INFO" "HELP"
        
        r = for i in (getINISetting s) where (i != "ABOUT" and i != "SCRIPT" and i != "COPY") collect i
        
        return #(n, a, v, o, r, c, h, t)
    )
	
	fn updateWorker = (
		m = dotnetobject "CSharpUtilities.SynchronizingBackgroundWorker"
		m.WorkerSupportsCancellation = true 
		m.CancelAsync() 
		dotNet.addEventHandler m "DoWork" bgUpdate
		m.RunWorkerAsync()	
	)
	
	on tmrRestart tick do (
		this = getThisScriptFileName()
		try(fileIn this) catch()
		vo = getIniSetting this "INFO" "VERSION"
		m = ("Script updated to version " + vo + "!\n\n\n")
		for c in (getIniSetting this vo) do (
			m += c + "\n"
		)
		
		messageBox m title: "Success!" beep: false
		tmrRestart.active = false
	)

    on _rAboutLP open do (
		updateWorker()
		
        i = getScriptInfo (getThisScriptFilename())
   
        lblName.caption = i[1]
        lblAuthor.caption = i[2]
        lblThanks.caption = i[8]
        lblVer.caption = i[3]
        lblCopy.address  = lblCopy.caption = i[6]
			
		floaterLibraryPacker.title = i[1] + " " +  i[3]
			
		x = '*'.get "x"
		y = '*'.get "y"
		
		if (x != "" and y != "") do (
			x = x as integer
			y = y as integer
			floaterLibraryPacker.pos = [x, y] 
		)
    )
	
	on _rAboutLP close do (
		p = floaterLibraryPacker.pos
		
		'*'.add "x" p.x
		'*'.add "y" p.y
	)	
)

rollout _rStepPlants "" category: 5 (
	multilistbox lbxLeft "ColorCorrect" across: 2 align: #left width: 160 height: 15	
	multilistbox lbxRight "MultiMap + ColorCorrect" align: #right width: 160	height: 15
	button btnApply "Apply" width: 361 height: 36
	button btnClear "Clear" width: 361 height: 18
	button btnToRight ">>" width: 26 height: 26 pos: [180, 95]
	button btnToLeft "<<" width: 26 height: 26 pos: [180, 125]
	
	
	local callbackSel = undefined
	local toLeft = #()
	local toRight = #()
	
	fn compareFN v1 v2 = (
		local d = v1[1] - v2[1]
		case of (
			(d < 0.): -1

			(d > 0.): 1
			default: 0
		)
	)

	fn listBoxMessage msg: "" clr: false = (
		if (clr) do (
			lbxLeft.items = #()
			lbxRight.items = #()
			return false
		)
		
		lbxLeft.items = #(msg)
		lbxRight.items = lbxLeft.items
	)
	
	fn displayLists = (
		lbxLeft.items = for i in 1 to toLeft.count collect formatString "[$1] $2" v: #(toLeft[i][1], toLeft[i][2].name)
		lbxRight.items = for i in 1 to toRight.count collect formatString "[$1] $2" v: #(toRight[i][1], toRight[i][2].name)
	)
	
	fn isPrefixExist n = (
		return findString n ::texturePrefix != undefined
	)
	
	fn autoLoadName = (
		if (_rLibraryPacker.cbxManualRename.checked) do return false
		
		s = selection[1]
		t = ""
		if (s != undefined) do t = s.name
		_rLibraryPacker.edtModelName.text = t
		_rLibraryPacker.checkModelName()
	)
	
	fn loadList = (
		autoLoadName()
		
		btnClear.enabled = false
		btnToLeft.enabled = false
		btnToRight.enabled = false
		btnApply.enabled = false
			
		if (selection.count == 0) do (
			listBoxMessage clr: true
			return false
		)
		if (selection.count > 1) do (
			listBoxMessage msg: "[!] Please select one object!"
			
			return false
		)
		
		if (selection[1].material == undefined) do (
			listBoxMessage msg: "[!] Object without material!"		
			return false
		)
		
		m = selection[1].material
		
		if (classOf m != MultiMaterial) do (
			listBoxMessage msg: "[!] No MultiMaterial!"		
			return false
		)
		
		lbxLeft.items = #()
		lbxRight.items = #()
		
		ids = m.materialIDList 
		mats = m.materialList
		
		toLeft = #()
		toRight = #()
	
		isCanRevert = false
		for i in 1 to mats.count where mats[i] != undefined do (
			mm = mats[i]
			if (classOf mm != CoronaMtl) do continue
			
			dd = mm.texmapDiffuse
			if (dd == undefined) do continue
			
			if (
				classOf dd == ColorCorrection \
				and isPrefixExist dd.name \
				and dd.map != undefined \
				and classOf dd.map == CoronaMultiMap \
				and isPrefixExist dd.map.name
			) do (
				append toRight #(ids[i], mm, m)
				isCanRevert = true
				
				continue
			)
			
			if (isPrefixExist dd.name) do isCanRevert = true
			append toLeft #(ids[i], mm, m)
		)
		
		btnClear.enabled = isCanRevert
		btnToLeft.enabled = toRight.count != 0
		btnToRight.enabled = toLeft.count != 0
		btnApply.enabled = (toRight.count + toLeft.count) > 0
		
		displayLists()		
	)
	
	fn updateList ev nd = (
		loadList()				
	)
		
	fn moveTo t: #right	= (		
		ids = if (t == #right) then lbxLeft.selection else lbxRight.selection
		ids = ids as array
		
		if (ids.count == 0) do return false
				
		for i in ids.count to 1 by -1 do (
			ii = ids[i]			
			if (t == #right) then append toRight toLeft[ii] else append toLeft toRight[ii]
		)
		
		for i in ids.count to 1 by -1 do (
			ii = ids[i]
			if (t == #right) then (try (deleteItem toLeft ii) catch ()) else (try (deleteItem toRight ii) catch ())
		)
		
		qsort toLeft compareFN
		qsort toRight compareFN
		
		displayLists()
		
		lbxLeft.selection = #{}
		lbxRight.selection = #{}
		
		btnToLeft.enabled = toRight.count != 0
		btnToRight.enabled = toLeft.count != 0
	)
	
	on _rStepPlants close do (
		callbackSel = undefined
		gc light:true
	)
	
	on _rStepPlants open do (
		gc light:true
		callbackSel = NodeEventCallback mouseUp:true delay:1000 selectionChanged: updateList
		
		loadList()
	)
	
	on btnToRight pressed do moveTo t: #right
	on btnToLeft pressed do moveTo t: #left
	
	fn findMMInstanceMaterials b = (	
		mm = for i in refs.dependents b where classOf i == MultiMaterial collect i
		if (mm[1] == undefined) do return undefined	
		mm = mm[1]
		
		cm = for i in refs.dependents b where classOf i == CoronaMtl collect i
			
		o = #()
		for i in cm do (
			z = findItem mm.materialList i
			if (z != 0) do o[z] = i
		)
		
		return for i in o where i != undefined collect i
	)
	
	fn removeMC m prop: #texmapDiffuse = (
		ret = false
		
		pp = getProperty m prop	
		if (pp == undefined) do return false
		
		n = pp.name
			
		if (isPrefixExist n) do (
			case (classOf pp) of (
				ColorCorrection: (
					setProperty m prop pp.map
					ret = true
				)
				CoronaMultiMap: (
					allInst = findMMInstanceMaterials pp
					
					if (allInst != undefined) do (
						for i in 1 to pp.texmaps.count where pp.texmaps[i] != undefined do (
							t = pp.texmaps[i]
							try (
								setProperty allInst[i] prop t
								ret = true
							) catch ()
						)
					)
				)
			)
		)
		
		return ret
	)
	
	fn clearPreparedMaterial m = (
		for z in 1 to 4 do (
			removeMC m prop: #texmapDiffuse
			removeMC m prop: #texmapTranslucency
		)
	)
	
	fn unlinkMultimaterialInstances m = (
		if (m == undefined or classOf m != MultiMaterial) do return false
		mm = m.materialList 
		uniqueMats = #()
		ret = false
		
		for i in 1 to mm.count do (
			if (not appendIfUnique uniqueMats mm[i]) do (
				mm[i] = copy mm[i]
				ret = appendIfUnique uniqueMats mm[i]			
			)
		)
		
		uniqueMats = #()
		
		return ret
	)
	
	fn addMultimat arr prop: #texmapDiffuse maxIds: 3 = (
		local multiMats = #()
		local isMultiMatsReached = false			
		
		local cnt = 1
		
		nn = toUpper (substituteString (prop as string) "texmap" "")
		
		tmp = CoronaMultiMap()
		tmp.name = texturePrefix + " MULTIMAP " + nn
		tmp.items = maxIds
		tmp.mode = 6
		tmp.seed = 1234
		
		cc = ColorCorrection()		
		cc.name = texturePrefix + " " + nn
		cc.map = tmp
		
		for i in arr do (
			m = i[2]
			mat = i[3]
			id = i[1]
			
			for z in 1 to 4 do removeMC m prop: prop
			
			pp = getProperty m prop
			if (pp != undefined and isMultiMatsReached) do (
				--setProperty m prop multiMats[cnt]
				
				slot = getMatById mat id
				if (slot != undefined) do replaceInstances slot multiMats[cnt]
				
				
				if (cnt == maxIds) do cnt = 0
				
				cnt += 1
			)
			if (pp != undefined and not isMultiMatsReached) do (
				tmp.texmaps[cnt] = pp
				setProperty m prop cc
				
				append multiMats m
				
				if (cnt == maxIds) do (
					isMultiMatsReached = true
					cnt = 0
				)
				
				cnt += 1
			)
		)
	)
	
	fn addColorCorrect arr prop: #texmapDiffuse = (		
		for i in arr do (
			m = i[2]
			
			nn = toUpper (substituteString (prop as string) "texmap" "")
			
			-- Remove			
			for z in 1 to 4 do removeMC m prop: prop
			
			pp = getProperty m prop
			if (pp != undefined) do (								
				cc = ColorCorrection()
				cc.name = texturePrefix + " " + nn
				cc.map = pp
				setProperty m prop cc
			)			
		)		
	)
	
	on btnApply pressed do (
		ss = selection[1]
		if (ss != undefined) do (
			unlinkMultimaterialInstances ss.material
		)
		
		addColorCorrect toLeft prop: #texmapDiffuse
		addColorCorrect toLeft prop: #texmapTranslucency
		
		addMultimat toRight prop: #texmapDiffuse
		addMultimat toRight prop: #texmapTranslucency
		
		loadList()
	)
	
	on btnClear pressed do (
		q = queryBox "Do you really want to clear (revert) material for selected object?" title: "Confirm?"
		if (not q) do return false
		
		for i in toLeft do clearPreparedMaterial i[2]
		for i in toRight do clearPreparedMaterial i[2]
			
		loadList()
	)
)

rollout _rStep1 "" category: 1 (
	checkbutton cbxModelsFlow "MODELS" align: #left width: 175 height: 26 checked: true highlightColor: ::colorHiglightItem across: 2
	checkbutton cbxPlantsFlow "PLANTS" align: #right width: 175 height: 26 highlightColor: ::colorHiglightItem offset: [1, 0]
	
	button btnRelinkBitmaps "1. Script Relink Bitmaps                                                                " width: 361 height: 18 offset: [0, 10] align: #left
	button btnConvertToVray "2. Convert to VRay         " width: 180 height: 18 align: #left across: 2
	button btnConvertToCorona "2. Convert to Corona" width: 180 height: 18 align: #left across: 2
	
	button btnPruneScene "3. Script Prune Scene                                                                  " width: 361 height: 18 align: #left
	button btnStockModelFixer "4. Script Stock Model Fixer                                                          " width: 361 height: 18 align: #left
	button btnAlbedo "5. Script Fix Albedo                                                                     " width: 361 height: 18 align: #left
	
	local сbxBtnList = #(cbxModelsFlow, cbxPlantsFlow)
	
	fn toggleFlow id = (
		for i in сbxBtnList do i.checked = false
		сbxBtnList[id].checked = true
		
		
		try (removeRollout _rStepPlants floaterLibraryPacker) catch()
		
		case id of (
			1: (
				_rLibraryPacker.cbxManualRename.checked = true
				_rLibraryPacker.cbxManualRename.enabled = false					
			)
			2: (
				addRollout _rStepPlants floaterLibraryPacker rolledUp: false border: false
				_rLibraryPacker.cbxManualRename.checked = false
				_rLibraryPacker.cbxManualRename.enabled = true
			)
		)
		
		
		_rLibraryPacker.toggleModelNameEnabled()
		_rLibraryPacker.checkModelName()
		
		::flowId = id
	)
	
	fn convertToVrayLaunchScript = (
		macros.run "[3DGROUND]" "RunCoronaToVrayConverter"
	)
	
	fn getMaxVersion = (
        v = maxVersion()
        v = (v[1] / 1000) - 2
        
        a = 2000 + v
        
        o = case v of 
        (
            11: #(a - 1, a)
            12: #(a - 2, a - 1, a)
            default: #(a - 3, a - 2, a - 1, a)
        )
        
        return (for i in o collect i as string)
    )
	
	fn convertToCorona = (
		try(
			renderers.current = CoronaRenderer()
			renderers.medit = CoronaRenderer()
		) catch (
			return messageBox "Corona Rednerer Engine not installed!" title: "Error!"
		)
		
		v = getMaxVersion()
		cv = v[v.count]
		
		f = getFiles ((getDir #scripts) + @"\CoronaRenderer\coronaConverter*.ms")
		f2 = getFiles (@"c:\Program Files\Corona\Corona Renderer for 3ds Max\" + cv + @"\Scripts\coronaConverter*.ms")
		
		join f f2
		
		if(f.count == 0) do (
			settingsScriptCC = '*'.get "CORONA_CONVERTER_SCRIPT"
			if (settingsScriptCC == "" or not doesFileExist settingsScriptCC) do (
				local jj = getOpenFileName types: "Script Files (*.ms)|*.ms" caption: "Please choose Corona Converter script"
				if (jj == undefined) do return false
				
				if (findString jj "Converter" == undefined) do (
					return messageBox "Please select correct Corona Converter script!" title: "Error!"
				)
				
				'*'.add "CORONA_CONVERTER_SCRIPT" jj
				f[1] = jj
			)
		)
		
		if(f.count == 0) do (
			return messageBox "Corona Converter script not found! Please choose script manually!" title: "Error!"
		)
		
		
		c = f[1]
		
		fileIn c
		fileIn c
		fileIn c
		
		if(::CoronaConverter == undefined) do return messageBox "Corona Converter script not found!" title: "Error!"
		
		::CoronaConverter.CoronaConverterRoll.chkClampIOR.checked = true		
		::CoronaConverter.converterSettings.clampIor = true
		
		::CoronaConverter.CoronaConverterRoll.spnClampedIOR.value = 10.0
		::CoronaConverter.converterSettings.clampIorAmount = 10.0
		
		::CoronaConverter.CoronaConverterRoll.chkSwitchRen.checked = true
		::CoronaConverter.converterSettings.switchRenderEngine = true
		
		::CoronaConverter.CoronaConverterRoll.chkConvVrayHDRI.checked = true
		::CoronaConverter.converterSettings.VrayHDRIToBitmaptexture = true
		
		::CoronaConverter.CoronaConverterRoll.chkCorPrefix.checked = false
		::CoronaConverter.converterSettings.addCoronaPrefix = false
			
		::CoronaConverter.convertScene()
		
		::CoronaConverter.converterTools.showMapsInVP true selected: false
		
		::CoronaConverter.converterTools.convertVrayDisplacementMods()
		::CoronaConverter.converterTools.fixCoronaNormalGamma()
		::CoronaConverter.converterTools.setPBRMode true
		
		::CoronaConverter.destroyGui()
		
		return true
	)
	
	on cbxModelsFlow changed v do toggleFlow 1
	on cbxPlantsFlow changed v do toggleFlow 2
	
	on btnRelinkBitmaps pressed do fileIn scriptRelinkBitmaps
	on btnPruneScene pressed do fileIn scriptPruneScene
	on btnStockModelFixer pressed do fileIn scriptStockModelFixer
	on btnAlbedo pressed do fileIn scriptAlbedo	
	on btnConvertToCorona pressed do convertToCorona()
	on btnConvertToVray pressed do convertToVrayLaunchScript()
	
	on _rStep1 open do (
		s1 = doesFileExist scriptRelinkBitmaps
		
		s2 = doesFileExist scriptConvertToVRay
		
		s3 = doesFileExist scriptPruneScene
		s4 = doesFileExist scriptStockModelFixer
		
		s5 = doesFileExist scriptAlbedo
		
		btnRelinkBitmaps.enabled = s1
		btnPruneScene.enabled = s3
		btnStockModelFixer.enabled = s4
		btnAlbedo.enabled = s5
		
		if (not s1) do btnRelinkBitmaps.caption = "Please Install Relink Bitmaps Script!"
		if (not s2) do btnConvertToVray.caption = "Please Install Corona2VRay Converter script!"
		if (not s3) do btnPruneScene.caption = "Please Install Prune Scene Script!"
		if (not s4) do btnStockModelFixer.caption = "Please Install Stock Model Fixer Script!"
		if (not s5) do btnAlbedo.caption = "Please Install Albedo Script!"
			
		if (not doesFileExist scriptModelpacker) do (
			messageBox "Please install Model Packer script!" title: "Error!"
			try(closeRolloutFloater floaterLibraryPacker) catch()
		)
		
		if (not isCoronaInstalled()) do (
			btnConvertToCorona.enabled = false
			btnConvertToCorona.caption = "Please Install Corona Renderer!"
		)
		
		toggleFlow 1
	)
)

rollout _rLibraryPacker "Library Packer" category: 10 (	
	global categoryMgr = #(#(), #(), #(), #())
	global offsetUI = 218
		
	group "Category (Models will be assigned GBuffer)" (		
		dropdownList ddlCat1 "" align: #left width: 342 across: 2
		checkbutton cbbIndicator1 ""  width: 12 height: 12 align: #right checked: true offset: [0, 3] enabled: false visible: false
		
		dropdownList ddlCat2 "" align: #left width: 342 across: 2 enabled: false
		checkbutton cbbIndicator2 ""  width: 12 height: 12 align: #right checked: true offset: [0, 3] enabled: false visible: false
		
		dropdownList ddlCat3 "" align: #left width: 342 across: 2 enabled: false
		checkbutton cbbIndicator3 ""  width: 12 height: 12 align: #right checked: true offset: [0, 3] enabled: false visible: false
		
		dropdownList ddlCat4 "" align: #left width: 342 across: 2 enabled: false -- can select but not create layer
		checkbutton cbbIndicator4 ""  width: 12 height: 12 align: #right checked: true offset: [0, 3] enabled: false visible: false
		
		dropdownList ddlCat5 "" align: #left width: 342 across: 2 enabled: false -- can select but not create layer
		checkbutton cbbIndicator5 ""  width: 12 height: 12 align: #right checked: true offset: [0, 3] enabled: false visible: false
	)
	
	group "Model Name" (
		dotNetControl edtModelName "System.Windows.Forms.TextBox" height: 25 width: 254 tabstop: true align: #left	across: 2
		checkbox cbxManualRename "Manual Rename" align: #right offset: [0, 3] checked: true
		label lblFinalModelName "" align: #left
	)
	
	group "Preview (Optional)" (
		dotNetControl btmPreview "System.Windows.Forms.PictureBox" width: 100 height: 100 align: #left
		
		label lblInfo1 "Drag&&Drop image to white box!" width: 154 align: #left pos: [120, 45 + offsetUI]
		label lblInfo2 "0 x 0 px" align: #left pos: [120, 65 + offsetUI]
		label lblDummy "" align: #left	pos: [120, 105 + offsetUI]	
	)
	
	group "Pack To Library" (
		edittext edtDir "" readonly: true across: 2 text: "Z:\\3D_Library\\" align: #left fieldwidth: 315 height: 22		
        button btnBrowse "..." width: 35 height: 24  align: #right offset: [1, -1]
		
		button btnPackToLibrary "Pack" width: 361 height: 36 offset: [0, 10]
	)
	
	local ddlsList = #(ddlCat1, ddlCat2, ddlCat3, ddlCat4, ddlCat5)
	local cbbsList = #(cbbIndicator1, cbbIndicator2, cbbIndicator3, cbbIndicator4, cbbIndicator5)
	
	fn updateCatStatus = (
		for i in 1 to ddlsList.count do cbbsList[i].visible = false
		for i in 1 to ddlsList.count do (
			c = cbbsList[i]
			d = ddlsList[i]
			
			isSelected = d.selection > 1
			isEnabled = d.enabled
			
			
			if (isSelected) then (
				c.checked = false
				c.highlightColor = color 10 194 10
				c.checked = true
				c.enabled = false
				c.visible = isEnabled
				
				continue
			)
			
			c.checked = false
			c.highlightColor = color 217 42 23
			c.checked = true
			c.enabled = false
			c.visible = isEnabled
			
			continue
		)
	)
	
	fn toggleModelNameEnabled = (
		edtModelName.enabled = cbxManualRename.checked
	)
	
	fn resetFresnelIorCorona = (
		try (
			for i in getClassInstances CoronaMtl do (
				if (i.fresnelIor > 900) do (
					i.fresnelIor = 10
				)
			)
		) catch()
	)
	
	fn addColorCorrectionToOtherMaterials = (
		for i in getClassInstances CoronaMtl where i != undefined and i.texmapDiffuse != undefined do (
			if (_rStepPlants.isPrefixExist i.texmapDiffuse.name) do continue
			cc = ColorCorrection()
			cc.name = texturePrefix + " DIFFUSE"
			cc.map = i.texmapDiffuse
			i.texmapDiffuse = cc
		)
	)
	
	
	fn getMaxFilesNames p = (
		return (for f in (getFiles (p + "*.max")) collect getFilenameFile f)
	)
	
	fn getDirs d = (
		o = #()
		for i in (getDirectories (d + "*")) do (
			p = filterString i @"\" splitEmptyTokens: false
			if (p.count < 2) do continue
			n = p[p.count]
			isContinue = false
			for ii in ignoreDirsPtrn do (
				if (matchPattern n pattern: ii) do isContinue = true
			)
			
			if (isContinue) do continue
			
			append o #(i, n)
		)
		
		return o
	)
	
	fn trim s tag: " " = (
		s as string
		return (trimLeft (trimRight s tag) tag)
	)
	
	fn isNumeric v = (
		v = trimLeft v "0123456789"
		return v == ""
	)
	
	fn getCatMgrList v = (
		d = #("")
		for i in v do append d i[2]
		return d
	)
	
	fn updateCatDdl = (		
		for i in 1 to ddlsList.count do (
			d = ddlsList[i]
			
			d.items = getCatMgrList categoryMgr[i]
			d.enabled = d.items.count > 1
				
			if (not d.enabled) do d.selection = 0
		)
	)
	
	fn getCategoryPath = (
		p = edtDir.text
		for i in 1 to ddlsList.count do (
			n = ddlsList[i].selected		
			
			if (not ddlsList[i].enabled) do continue
			if (n == undefined or n == "") do return undefined
			
			p += n + @"\"
		)
		
		return p
	)
	
	fn getCategoryUniqueId = (
		id = ""
		for i in 1 to ddlsList.count do (
			j = ddlsList[i].selected
			if (not ddlsList[i].enabled) do continue
			if (j == undefined or j == "") do return ""
			z = (FilterString j "_.")[1]
			if (z[1] == "0") do z = substring z 2 z.count 
			id += z
		)
		
		return id
	)
	
	fn getFinalName = (
		n = edtModelName.text
		cp = getCategoryPath()
		
		id = getCategoryUniqueId()
		
		if (n == "") do return undefined
		if (id == "") do return undefined
		return n + "_" + id
	)
	
	fn checkModelName = (
		n = edtModelName.text
		cp = getCategoryPath()
		
		if (cp == undefined) do (
			return lblFinalModelName.caption = "Please select all categories!"
		)
		
		if (n.count < 1) do (
			return lblFinalModelName.caption = "Please enter Model Name!"
		)
		
		nn = getFinalName()
		
		t = ""
		if (nn != undefined) do t = nn
		lblFinalModelName.caption = "Name: " + t
	)
	
	fn addSuggestRange = (
		pp = getCategoryPath()
		
		if (pp == undefined) do return false
		
		ff = getMaxFilesNames pp		
		edtModelName.AutoCompleteCustomSource.AddRange ff
	)
	
	fn loadCat lvl: 1 = (
		::isCategorySelected = false
		-- New logic changed
		if (not cbxManualRename.checked) do edtModelName.enabled = false
		--edtModelName.enabled = true
		
		::MODEL_PACKER_USE_API = undefined
		
		updateCatStatus()
		for i in 1 to ddlsList.count do categoryMgr[i] = #()
		for i in lvl to ddlsList.count do ddlsList[i].selection = 0
		
		local p = edtDir.text
		categoryMgr[1] = getDirs p
	
		for i in 2 to ddlsList.count do (
			d = ddlsList[i - 1]			
			if (d.selected == undefined or d.selected.count < 2) do (				
				exit
			)
			
			p += d.selected + @"\"
			categoryMgr[i] = getDirs p
		)
		
		updateCatDdl()
		
		pp = getCategoryPath()
		
		updateCatStatus()
		checkModelName()
		if (pp == undefined) do return false
		
		addSuggestRange()
		
		::isCategorySelected = true
		--edtModelName.enabled = true
	)
		
	fn getGBuffer = (		
		if (ddlCat1.selected == undefined) do return 0
		nn = filterString (ddlCat1.selected) "_."
		n = nn[1]
		if (not isNumeric n) do return 0
		
		return try (n as integer) catch (return 0)
	)
	
	fn getStringGBuffer = (
		g = getGBuffer()		
		g = g as string
		
		if (g.count == 1) do g = "0" + g
		
		return g		
	)
	
	fn moveObjectsToLayers = (
		gbuffer = getStringGBuffer()
		
		ll = #()
		
		n1 = ddlCat1.selected
		n2 = ddlCat2.selected
		n3 = ddlCat3.selected
		
		if (n1 != undefined) do append ll n1
		if (n2 != undefined) do append ll (n2 + "_" + gbuffer)
		if (n3 != undefined) do append ll (n3 + "_" + gbuffer)
		
		y = undefined
		for i in 1 to ll.count do (
			l = LayerManager.newLayerFromName ll[i]
			
			if (l == undefined) do (
				l = LayerManager.getLayerFromName ll[i]
				if (l == undefined) do continue
			)
			
			if (y != undefined) do l.setParent y
			y = l
			
			if (i == ll.count) do (
				for o in objects where superClassOf o != light do l.addNode o
				
				if (lights.count > 0) do (
					la = LayerManager.newLayerFromName ("Lights_" + edtModelName.text)
					for o in lights do la.addNode o
					la.setParent y
				)
				
			)
		)
	)
	
	fn clearChildrenLayers l = (
		if(l == undefined) do return false
		num = l.getNumChildren()
		if(num > 0) then 
		(
			for ll in num to 1 by -1  do
			(
				c = l.getChild ll
				if c != undefined do 
				(	
					clearChildrenLayers c
				)
			)
		)
		else
		(
			n = undefined
			l.nodes &n
			
			if n.count == 0 do 
			(	
				layerManager.deleteLayerByName l.name				
			)
		)				
	)
	
	fn removeLayers = (
		layersCount = layerManager.count
		v = maxVersion()
		
		isOldMax = v[1] < 17000
		
		c = 0
		(layerManager.getLayer 0).current = true
		
		
		if(isOldMax == true) then
		(
			for l = layerManager.count to 2 by -1 do
			(
				la = layerManager.getLayer (l - 1)
				
				n = undefined
				la.nodes &n
				
				if n.count == 0 do 
				(	
					layerManager.deleteLayerByName la.name
					c += 1
				)
			)
		)
		else
		(
			for l = layerManager.count to 2 by -1 do
			(
				la = layerManager.getLayer (l - 1)
				c = clearChildrenLayers la
			)
		)
			
		return (layersCount - layerManager.count)
	)
	
	fn removeForestLayers = (
		removeLayers()
		
		ptrn = "_forest_template*"
		objs = for o in objects where (matchPattern o.name pattern: ptrn) collect o
		delete objs
			
		removeLayers()
		removeLayers()
	)
		
	fn setGBuffer = (
		i = getGBuffer()
		
		for o in objects where superClassOf o != light do try (o.gbufferchannel = i) catch()
		
		return true
	)
	
	fn clearPreview = (
		btmPreview.image = undefined
		::previewModelPath = ""
		lblInfo2.caption = "0 x 0 px"
		lblInfo1.caption = "Drag&&Drop image to white box!"
	)
	
	fn loadPreview f = (
		local fs = dotnetObject "System.IO.FileStream" f (dotnetClass "System.IO.FileMode").open
		local tempBmp = dotnetObject "System.Drawing.Bitmap" fs
		local resultBmp = tempBmp.Clone()
		tempBmp.Dispose()
		fs.Close()
		btmPreview.image = resultBmp
		
		w = resultBmp.width as string
		h = resultBmp.height as string
		lblInfo2.caption = w + " x " + h + " px"
		lblInfo1.caption = filenameFromPath f
	)
	
	fn contextClearPreview = (
		clearPreview()
	)
	
	on cbbIndicator1 changed v do cbbIndicator1.checked = true
	on cbbIndicator2 changed v do cbbIndicator2.checked = true
	on cbbIndicator3 changed v do cbbIndicator3.checked = true
	on cbbIndicator4 changed v do cbbIndicator4.checked = true
		
	on edtModelName KeyUp s a do (
		--showEvents edtModelName
		checkModelName()
	)
	
	on btmPreview mouseDown ss a do (
		ss.ContextMenuStrip = undefined
		
		if (a.button != ss.MouseButtons.Right) do return false
		
		contextMenu = dotNetObject "System.Windows.Forms.ContextMenuStrip"
		
		li1 = contextMenu.Items.Add("Clear")
		
		dotNet.addEventHandler (li1) "Click" contextClearPreview
		
		ss.ContextMenuStrip = contextMenu
	)
	
	on cbxManualRename changed v do (
		edtModelName.enabled = v
	)
		
	on ddlCat1 selected v do loadCat lvl: 2
	on ddlCat2 selected v do loadCat lvl: 3
	on ddlCat3 selected v do loadCat lvl: 4
	on ddlCat4 selected v do loadCat lvl: 5
	on ddlCat5 selected v do loadCat lvl: 6
	
	on btnBrowse pressed do (
		p = getSavePath()
		if (p == undefined) do return false		
		p += @"\"
		
		edtDir.text = p
		
		'*'.add "LIB_DIR" p
		
		loadCat()
	)
	
	on _rLibraryPacker open do (
		::MODEL_PACKER_USE_API = undefined
		
		::previewModelPath = ""
		
		freezeUi()
		
		p = '*'.get "LIB_DIR"
		if (p != "" and doesFileExist p) do edtDir.text = p
		
		loadCat()
		
		edtModelName.AutoCompleteMode = _rLibraryPacker.edtModelName.AutoCompleteMode.SuggestAppend
        edtModelName.AutoCompleteSource = _rLibraryPacker.edtModelName.AutoCompleteSource.CustomSource
        edtModelName.AcceptsReturn = true
        edtModelName.AcceptsTab = true
        edtModelName.TabStop = true
		--showProperties edtModelName
		
		btmPreview.AllowDrop = true
		btmPreview.SizeMode = (dotNetclass "System.Windows.Forms.PictureBoxSizeMode").Zoom  
		
		toggleModelNameEnabled()
	)
	
	on btmPreview DragOver s e do (
		e.Effect = if (e.data.ContainsFileDropList()) then (e.Effect.Move) else (e.Effect.None)
	)
	
	on btmPreview DragDrop s e do (
		::previewModelPath = ""
		allowedTypes = #(".jpg", ".png", ".gif", ".jpeg")
		
		if (not e.data.ContainsFileDropList()) do return false
			
		data = e.data.GetFileDropList()
		files = for k in 0 to (data.count - 1) collect data.item[k]
		files = for i in files where findItem allowedTypes (getFilenameType i) != 0 collect i
		
		if (files.count == 0) do return false
			
		f = files[1]
		::previewModelPath = f
		loadPreview f
	)
	
	on btnPackToLibrary pressed do (
		edtModelName.text = trim (edtModelName.text)
		
		SetQuietMode false
		
		if (objects.count == 0) do  return messageBox "Please add objects to scene!" title: "Warning!"
		if (not isValidRender()) do return messageBox "Please assign Corona or VRay Renderer Engine!" title: "Error!"
		tt = isValidText edtModelName.text
		if (edtModelName.text.count == 0) do return messageBox "Please enter Model Name!" title: "Error!"
		if (tt != true) do return messageBox tt title: "Error!"
			
		cp = getCategoryPath()
		if (cp == undefined) do return messageBox "Please choose all categories!" title: "Error!"
			
		finalName = getFinalName()				
		if (finalName == undefined) do return messageBox "Please something wrong with Model Name!" title: "Error!"	
			
		if (doesFileExist (cp + finalName + ".max")) do return messageBox "Model with the same name already exist in Library\nPlease choose another name!" title: "Error!"
			
		removeForestLayers()
		setGBuffer()
		--moveObjectsToLayers()
		resetFresnelIorCorona()
		addColorCorrectionToOtherMaterials()
		
		SetQuietMode false
			
		p = case cbxManualRename.checked of (
			false: ::MODEL_PACKER_PRESET_NORENAME
			default: ::MODEL_PACKER_PRESET
		)
		
		try(global MODEL_PACKER_USE_API = true) catch()
		-- Run Model Packer
			
		try(fileIn scriptModelpacker) catch(
			::MODEL_PACKER_USE_API = undefined
			messageBox "Can't run the ModelPacker script!" title: "Error!"
			return false
		)
		
		-- Available from ver 1.4.4
		if(::MODEL_PACKER_API == undefined) do (
			messageBox "Model packer API not found! Please update the script!" title: "Error!"
			return false
		)
		
		api = ::MODEL_PACKER_API()
		if(not api.usePreset p) do (
			::MODEL_PACKER_USE_API = undefined
			messageBox ("Preset \"" + p + "\" not found in Model Packer presets list!") title: "Error!"
			return false
		)
		
		::MODEL_PACKER_USE_API = undefined
		
		-- Set quet mode
		clearSelection()
		select objects
		
		::MODEL_PACKER_USE_API = true
		
		try(fileIn scriptModelpacker) catch()
		
		api = ::MODEL_PACKER_API()
		
		if(not api.usePreset p) do (
			return messageBox ("Can't set \"" + p + "\" preset!") title: "Error!"			
		)
		
		ff = cp + finalName + ".zip" 
		
		-- Save Preview
		if (::previewModelPath != undefined and ::previewModelPath != "") do (
			previewFile = cp + (substituteString finalName " " "_") + ".max" + (getFileNameType ::previewModelPath)
			copyFile ::previewModelPath previewFile
		)
		
		api.inputData (
			struct data (
				product_url = "",
				filename = ff,
				name = finalName, 
				manufacturer = "",
				modeller = "",
				site = "",
				tags = "",
				overview = "",
				custom1 = "",
				previews = #(),
				vendor = undefined
			)
		)
		
		SetQuietMode true
		status = api.beginPack()
		SetQuietMode false
		
		clearPreview()
		
		
		if (status == #packed_success) then (
			edtModelName.text = ""
			for i in ddlsList do try (i.selection = 0) catch()
			q = queryBox "Packed success!\nDo you want to open destination folder?" title: "Confirm?"
			if (q) do shellLaunch cp ""			
		) else (
			m =  "Error while packing " + finalName + "! Status code: " + status
			messageBox m title: "Error!"
		)
		
		::MODEL_PACKER_USE_API = undefined
		
		updateCatStatus()
		boost()
	)
)


addRollout _rLibraryPacker floaterLibraryPacker rolledUp: false border: false
addRollout _rStep1 floaterLibraryPacker rolledUp: false border: false
addRollout _rAboutLP floaterLibraryPacker rolledUp: true 