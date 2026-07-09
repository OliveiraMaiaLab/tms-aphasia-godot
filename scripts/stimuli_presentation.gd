extends Node2D

# Declare member variables here. Examples:
#var image_folder = "res://imagens/stimuli"
var image_folder = "user://stimuli"
var difficulty_folder = ""
var figure_path = "res://imagens/stimuli/0/actions/act266win.jpg"

var image_paths: Array
var answers = {"block1": [],
				"trial_start": [],
				"trial_end": [],
				"image": [],
				"success": []}

var trial_start_timestamp = OS.get_unix_time()
var task_start_timestamps = OS.get_unix_time()
var success = true

var rsp_freeze_time = 0.5					# time in s
var image_presentation_max_duration = 20	# time in s
var interblock_time = 20					# time in s
var block_duration = 1						# time in min

var rsp_freeze = true
var change_image = false
var block1 = true

var interblock_timer
var block_timer
var image_presentation_timer

# Called when the node enters the scene tree for the first time.
func _ready():
# warning-ignore:return_value_discarded
	self.get_parent().get_node('main_menu/start_button').connect("pressed", self, "_on_start_press")
	hide_interblock()
	hide_stimuli()
	show_menu()

# ==================================================================================================
# 									Show and hide Nodes Functions
# --------------------------------------------------------------------------------------------------
func hide_menu():
	self.get_parent().get_node('main_menu/start_button').disabled = true
	self.get_parent().get_node('main_menu').visible = false
	self.visible = true

func show_menu():
	# show menu node and activate button
	self.get_parent().get_node('main_menu/start_button').disabled = false
	self.get_parent().get_node('main_menu').visible = true
	
func hide_interblock():
	# hide inter block interval node and deactivate advance buttons
	self.get_parent().get_node('inter_block_int/vbox/advance_button').disabled = true
	self.get_parent().get_node('inter_block_int').visible = false
	
func show_interblock():
	# hide inter block interval node and deactivate advance buttons
	self.get_parent().get_node('inter_block_int/vbox/advance_button').disabled = false
	self.get_parent().get_node('inter_block_int').visible = true

func hide_stimuli():
	# hide stimuli node
	self.visible = false
	self.get_node('Sprite').visible = false	
	
func show_stimuli():
	# hide stimuli node
	self.visible = true
	self.get_node('Sprite').visible = true	

# ==================================================================================================
# 										Timer functions
# --------------------------------------------------------------------------------------------------

func start_interblock_timer():
	interblock_timer = Timer.new()
	interblock_timer.set_wait_time(interblock_time)
	interblock_timer.connect("timeout",self,"_on_interblock_timout")
	# Add to the tree as child of the current node
	add_child(interblock_timer)
	# start timer
	interblock_timer.one_shot = true
	interblock_timer.start() 

func start_block_timer():
	block_timer = Timer.new()
	block_timer.set_wait_time(block_duration * 60)
	block_timer.connect("timeout",self,"_on_block_timout")
	# Add to the tree as child of the current node
	add_child(block_timer)
	# start timer
	block_timer.one_shot = true
	block_timer.start() 

func next_image_timer():
	image_presentation_timer = Timer.new()
	image_presentation_timer.set_wait_time(image_presentation_max_duration - rsp_freeze_time)
	image_presentation_timer.connect("timeout",self,"_image_presentation_timout")
	# Add to the tree as child of the current node
	add_child(image_presentation_timer)
	# start timer
	image_presentation_timer.one_shot = true
	image_presentation_timer.start() 

func freeze_change():
	yield(get_tree().create_timer(rsp_freeze_time), "timeout")
	rsp_freeze = false
	change_image = true

# Timer signals

func _on_interblock_timout():
	start_block_timer()
	hide_menu()
	hide_interblock()
	block1 = false
	start_block_images()
	change_texture()
	show_stimuli()

func _on_block_timout():
	success = false
	push_answers()
	save(answers)
	image_presentation_timer.stop()
	if block1:
		show_interblock()
		start_interblock_timer()
		hide_stimuli()
		hide_menu()
	else:
		hide_interblock()
		hide_stimuli()
		show_menu()

func _image_presentation_timout():
	success = false
	push_answers()
	save(answers)
	change_texture()

# ==================================================================================================
# 											Get Image Paths
# --------------------------------------------------------------------------------------------------

func get_dir_contents(path) -> Array:
	var files = []
	var directories = []
	var dir = Directory.new()
	if dir.open(path) == OK:
		dir.list_dir_begin(true, false)
		_add_dir_contents(dir, files, directories)
	else:
		push_error("An error occurred when trying to access the path.")
	print(files)
	return files

func _add_dir_contents(dir: Directory, files: Array, directories: Array):
	var file_name = dir.get_next()
	while (file_name != ""):
		var path = dir.get_current_dir() + "/" + file_name
		if dir.current_is_dir():
#			print("Found directory: %s" % path)
			var subDir = Directory.new()
			subDir.open(path)
			subDir.list_dir_begin(true, false)
			directories.append(path)
			_add_dir_contents(subDir, files, directories)
		else:
#			print("Found file: %s" % path)
			if not('.import' in path):
				files.append(path)
		file_name = dir.get_next()
	dir.list_dir_end()

func start_block_images():
	var part = ''
	if block1:
		part = 'objects'
	else:
		part = 'actions'
	difficulty_folder = '%s/%s/%s/' % [image_folder, self.get_parent().get_node("main_menu/difficulty_hbox/option_button").selected, part]
	image_paths = get_dir_contents(difficulty_folder)

# ==================================================================================================
# 											Change Images
# --------------------------------------------------------------------------------------------------

func load_texture(path):
	var tex_file = File.new()
	tex_file.open(path, File.READ)
	var bytes = tex_file.get_buffer(tex_file.get_len())
	var img = Image.new()
	if 'png' in path:
		var _data = img.load_png_from_buffer(bytes)
	elif 'jpg' in path:
		var _data = img.load_jpg_from_buffer(bytes)
	var imgtex = ImageTexture.new()
	imgtex.create_from_image(img)
	tex_file.close()
	$Sprite.texture = imgtex

func _change_texture():
	rsp_freeze = true
	# get random image
	var random_i = randi() % int(image_paths.size())
	figure_path = image_paths[random_i]
	# remove random item from paths
	image_paths.remove(random_i)
	# change image
	load_texture(figure_path)
	freeze_change()
	next_image_timer()

func change_texture():
	trial_start_timestamp = OS.get_ticks_msec()
	if image_paths.size() != 0:
		_change_texture()
	else:
		start_block_images()
		_change_texture()

# ==================================================================================================
# 											Save Data
# --------------------------------------------------------------------------------------------------

func save(content):
	var fpath = "user://aphasia_stim_registration_%s.json" % [String(task_start_timestamps)]
	var file = File.new()
	file.open( str(fpath), File.WRITE) 
	file.store_line(to_json(content))
	file.close()
	
func push_answers():
	answers["block1"].push_back(block1)
	answers["trial_start"].push_back(trial_start_timestamp)
	answers["trial_end"].push_back(OS.get_ticks_msec())
	answers["image"].push_back(figure_path)
	answers["success"].push_back(success)

# ==================================================================================================
# 											User interaction
# --------------------------------------------------------------------------------------------------

func _on_start_press():
	task_start_timestamps = OS.get_unix_time()
	start_block_timer()
	hide_menu()
	hide_interblock()
	block1 = true
	start_block_images()
	change_texture()
	show_stimuli()

func _input(_event):
	# Esc to Exit Program
	if Input.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if Input.is_action_pressed("ui_advance"):
		print('ui_advance')
		if not(rsp_freeze):
			success = true
			push_answers()
			save(answers)
			image_presentation_timer.stop()
			change_texture()
	if Input.is_action_pressed("ui_focus_next"):
		print('ui_focus_next')
		image_presentation_timer.stop()
		block_timer.stop()
		hide_interblock()
		hide_stimuli()
		show_menu()
