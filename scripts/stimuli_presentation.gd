extends Node2D
# Objects/actions naming task controller. block1 = objects block, block2 = actions block.
# See stimulus_task_explained.md for a full write-up.

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
const LOG_TAG := "[StimulusTask]"   # prefix on every log line
const VERBOSE_FILE_SCAN := false    # true = log every file/folder scanned (noisy)

func _log(message: String) -> void:
	print("%s %s" % [LOG_TAG, message])

# --------------------------------------------------------------------------
# Stimuli source
# --------------------------------------------------------------------------
var image_folder = "res://imagens/stimuli/"                        # root stimuli folder
var difficulty_folder = ""                                         # active folder path
var figure_path = "res://imagens/stimuli/0/actions/act266win.jpg"  # image on screen
var image_paths: Array = []                                        # images left in this block

# Trial log, parallel arrays (same index = same trial), dumped to JSON after each trial.
var answers = {
	"block1": [],       # true = objects block, false = actions block
	"trial_start": [],  # engine ticks (ms) image appeared
	"trial_end": [],    # engine ticks (ms) trial ended
	"image": [],        # image path shown
	"success": []       # true if participant responded before timeout
}

var trial_start_timestamp = Time.get_unix_time_from_system()
var task_start_timestamps = Time.get_unix_time_from_system()
var success = true
var rsp_freeze_time = 0.5                  # time in s
var image_presentation_max_duration = 20   # time in s
var interblock_time = 20                   # time in s
var block_duration = 1                     # time in min
var rsp_freeze = true       # true = ignore input (freeze period after image appears)
var block1 = true           # true = block 1 (objects), false = block 2 (actions)
var interblock_timer: Timer
var block_timer: Timer
var image_presentation_timer: Timer

# Called when the node enters the scene tree for the first time.
func _ready():
	print("[Info] Godot app started")
	get_parent().get_node("main_menu/start_button").pressed.connect(_on_start_press)
	hide_interblock()
	hide_stimuli()
	show_menu()
# ==================================================================================================
# 									Show and hide Nodes Functions
# --------------------------------------------------------------------------------------------------
func hide_menu():
	get_parent().get_node("main_menu/start_button").disabled = true
	get_parent().get_node("main_menu").visible = false

func show_menu():
	# show menu node and activate button
	get_parent().get_node("main_menu/start_button").disabled = false
	get_parent().get_node("main_menu").visible = true

func hide_interblock():
	# hide inter block interval node and deactivate advance buttons
	get_parent().get_node("inter_block_int/vbox/advance_button").disabled = true
	get_parent().get_node("inter_block_int").visible = false

func show_interblock():
	# show inter block interval node and activate advance buttons
	get_parent().get_node("inter_block_int/vbox/advance_button").disabled = false
	get_parent().get_node("inter_block_int").visible = true

func hide_stimuli():
	# hide stimuli node
	$Sprite.visible = false

func show_stimuli():
	# show stimuli node
	$Sprite.visible = true
# ==================================================================================================
# 										Timer functions
# --------------------------------------------------------------------------------------------------
func start_interblock_timer() -> void:
	# countdown between block 1 (objects) and block 2 (actions)
	print("[INFO] Starting inter-block timer (%ds)" % interblock_time)
	interblock_timer = Timer.new()
	interblock_timer.wait_time = interblock_time
	interblock_timer.timeout.connect(_on_interblock_timout)
	add_child(interblock_timer)
	interblock_timer.one_shot = true
	interblock_timer.start()

func start_block_timer() -> void:
	# overall time limit for the current block
	print("[INFO] Starting block timer (%s min)" % str(block_duration))
	block_timer = Timer.new()
	block_timer.wait_time = block_duration * 60
	block_timer.timeout.connect(_on_block_timout)
	add_child(block_timer)
	block_timer.one_shot = true
	block_timer.start()

func next_image_timer() -> void:
	# per-trial response window; timeout = failed trial
	image_presentation_timer = Timer.new()
	image_presentation_timer.wait_time = image_presentation_max_duration - rsp_freeze_time
	image_presentation_timer.timeout.connect(_image_presentation_timout)
	add_child(image_presentation_timer)
	image_presentation_timer.one_shot = true
	image_presentation_timer.start()

func freeze_change() -> void:
	# ignore input briefly so a leftover key press isn't scored as this trial's response
	await get_tree().create_timer(rsp_freeze_time).timeout
	rsp_freeze = false

# Timer signals
func _on_interblock_timout():
	print("[INFO] Inter-block interval finished - starting block 2 (actions)")
	start_block_timer()
	hide_menu()
	hide_interblock()
	block1 = false
	start_block_images()
	change_texture()
	show_stimuli()

func _on_block_timout():
	print("[INFO] Block timer expired - ending %s" % ("block 1 (objects)" if block1 else "block 2 (actions)"))
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
	_log("No response within %ds - marking trial as failed" % image_presentation_max_duration)
	success = false
	push_answers()
	save(answers)
	change_texture()
# ==================================================================================================
# 											Get Image Paths
# --------------------------------------------------------------------------------------------------
func get_dir_contents(path: String) -> Array:
	# recursively collect every non-".import" file under path
	var files = []
	var directories = []
	var dir = DirAccess.open(path)
	if dir:
		dir.include_navigational = false
		dir.include_hidden = true
		dir.list_dir_begin()
		_add_dir_contents(dir, files, directories)
		_log("Found %d stimulus file(s) in '%s'" % [files.size(), path])
		if files.is_empty():
			push_warning("%s No stimulus files found in '%s' - check the folder path and difficulty setting." % [LOG_TAG, path])
	else:
		push_error("%s Could not open stimuli folder '%s' (error %d)" % [LOG_TAG, path, DirAccess.get_open_error()])
	return files

func _add_dir_contents(dir: DirAccess, files: Array, directories: Array):
	# one directory level per call, so subfolders recurse with their own DirAccess
	var file_name = dir.get_next()
	while file_name != "":
		var path = dir.get_current_dir() + "/" + file_name
		if dir.current_is_dir():
			if VERBOSE_FILE_SCAN:
				_log("  entering directory: %s" % path)
			var sub_dir = DirAccess.open(path)
			if sub_dir:
				sub_dir.include_navigational = false
				sub_dir.include_hidden = true
				sub_dir.list_dir_begin()
				directories.append(path)
				_add_dir_contents(sub_dir, files, directories)
		else:
			if not (".import" in path):
				if VERBOSE_FILE_SCAN:
					_log("  found file: %s" % path)
				files.append(path)
		file_name = dir.get_next()
	dir.list_dir_end()

func start_block_images():
	# point image_paths at the current block's folder (objects/actions x difficulty)
	var part = "objects" if block1 else "actions"
	var difficulty: int = get_parent().get_node("main_menu/difficulty_hbox/option_button").selected
	difficulty_folder = "%s/%s/%s/" % [image_folder, difficulty, part]
	_log("Loading '%s' stimuli (difficulty %d) from '%s'" % [part, difficulty, difficulty_folder])
	image_paths = get_dir_contents(difficulty_folder)
# ==================================================================================================
# 											Change Images
# --------------------------------------------------------------------------------------------------
func load_texture(path: String) -> void:
	# load + decode an image file and display it, logging on any failure
	var tex_file = FileAccess.open(path, FileAccess.READ)
	if tex_file == null:
		push_error("%s Could not open image '%s' (error %d)" % [LOG_TAG, path, FileAccess.get_open_error()])
		return
	var bytes = tex_file.get_buffer(tex_file.get_length())
	var img = Image.new()
	var decode_err := OK
	if "png" in path:
		decode_err = img.load_png_from_buffer(bytes)
	elif "jpg" in path:
		decode_err = img.load_jpg_from_buffer(bytes)
	else:
		push_warning("%s Unrecognized image extension for '%s' - expected .png or .jpg" % [LOG_TAG, path])
	tex_file.close()
	if decode_err != OK:
		push_error("%s Failed to decode image '%s' (error %d)" % [LOG_TAG, path, decode_err])
		return
	var imgtex = ImageTexture.create_from_image(img)
	$Sprite.texture = imgtex
	_log("Loaded stimulus image: %s" % path)

func _change_texture():
	# pick a random remaining image, show it, arm freeze + timeout
	rsp_freeze = true
	var random_i = randi() % int(image_paths.size())
	figure_path = image_paths[random_i]
	image_paths.remove_at(random_i)
	_log("Presenting image %s (%d remaining in pool)" % [figure_path, image_paths.size()])
	load_texture(figure_path)
	freeze_change()
	next_image_timer()

func change_texture():
	# advance to next trial, refilling the pool once it's empty
	trial_start_timestamp = Time.get_ticks_msec()
	if image_paths.size() != 0:
		_change_texture()
	else:
		print("[INFO] Image pool exhausted - reloading stimuli for the current block")
		start_block_images()
		_change_texture()
# ==================================================================================================
# 											Save Data
# --------------------------------------------------------------------------------------------------
func save(content) -> void:
	# overwrite this session's JSON log with the full trial history so far
	var fpath = "user://aphasia_stim_registration_%s.json" % [str(task_start_timestamps)]
	var file = FileAccess.open(fpath, FileAccess.WRITE)
	if file == null:
		push_error("%s Could not open '%s' for writing (error %d) - trial data was NOT saved." % [LOG_TAG, fpath, FileAccess.get_open_error()])
		return
	file.store_line(JSON.stringify(content))
	file.close()
	_log("Saved %d trial(s) to %s" % [content["trial_start"].size(), fpath])

func push_answers():
	# append the just-finished trial to answers
	answers["block1"].push_back(block1)
	answers["trial_start"].push_back(trial_start_timestamp)
	answers["trial_end"].push_back(Time.get_ticks_msec())
	answers["image"].push_back(figure_path)
	answers["success"].push_back(success)
	_log("Trial %d recorded - block: %s, image: %s, success: %s" % [
		answers["image"].size(),
		"objects" if block1 else "actions",
		figure_path,
		success
	])
# ==================================================================================================
# 											User interaction
# --------------------------------------------------------------------------------------------------
func _on_start_press():
	print("[INFO] Objects block started")
	task_start_timestamps = Time.get_unix_time_from_system()
	_log("Task started at unix time %s - beginning block 1 (objects)" % str(task_start_timestamps))
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
		print("[INFO] Quit requested (ui_cancel)")
		get_tree().quit()
	# Enter or Space to move to next image
	if Input.is_action_pressed("ui_accept"):
		if not rsp_freeze:
			_log("Response accepted (ui_accept)")
			success = true
			push_answers()
			save(answers)
			image_presentation_timer.stop()
			change_texture()
	# tab to go back to the menu
	if Input.is_action_pressed("ui_focus_next"):
		print("[INFO] Manual return to menu (ui_focus_next)")
		image_presentation_timer.stop()
		block_timer.stop()
		hide_interblock()
		hide_stimuli()
		show_menu()
