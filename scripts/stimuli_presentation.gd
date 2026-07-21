
extends Node2D
# Objects/actions naming task controller. block1 = objects block, block2 = actions block.
# See stimulus_task_explained.md for a full write-up.

# --------------------------------------------------------------------------
# Version info
# --------------------------------------------------------------------------
const VERSION := "1.1.0"
const VERSION_DATE := "2024-06-10"
const VERSION_NOTE := "Added inter-block interval and block timer, plus stimulus pool reloading."
const GODOT_VERSION := "4.7-stable_win64"

# --------------------------------------------------------------------------
# Task Parameters
# --------------------------------------------------------------------------

const block_duration : int = 1								# duration (min) to run each block
const image_presentation_max_duration : int = 20			# max time (s) to present image
const interblock_time : int = 20							# max time (s) between blocks
const rsp_freeze_time : float = .5                  		# time (s) to ignore input after image appears 
const images_folder : String = "res://imagens/stimuli/"	# root stimuli folder

# --------------------------------------------------------------------------
# Output data structure and variables
# --------------------------------------------------------------------------

var trial : int = 0
var difficulty : int
var block_type : String = 'objects'
var image_relpath : String
var success : bool
var task_start_timestamp : float = Time.get_unix_time_from_system()	# start and end
var app_start_timestamp : float = Time.get_unix_time_from_system()

var answers = {
	"trial": [],			# trial number
	"difficulty": [],		# 0 | 1 | 2
	"block_type": [],		# objects | actions
	"image": [],			# stimulus image relative path
	"success": [],			# true if participant responded before timeout
	"trial_start": [],		# timestamp (ms) trial started
	"trial_end": [],		# timestamp (ms) trial ended
	"task_start": [],		# timestamp (s) task started
	"app_start": [],		# timestamp (s) app started
	"version": [],			# version of this script
}

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
const TASK_LOG_TAG := "[StimulusTask]"	# prefix on every task related log line
const INFO_LOG_TAG := "[INFO]"   		# prefix on ?other? log line

func _log_info(message: String) -> void:
	print("%s %s" % [INFO_LOG_TAG, message])

func _log_task(message: String) -> void:
	print("%s %s" % [TASK_LOG_TAG, message])

# --------------------------------------------------------------------------
# Task flow variables
# --------------------------------------------------------------------------
var _figure_path : String 	# image on screen
var _image_paths: Array		# images left in this block
var _timestamps : float = Time.get_unix_time_from_system() # for all other timestamps
var _rsp_freeze : bool = true       # true = ignore input (freeze period after image appears)
# Timers
var interblock_timer: Timer
var block_timer: Timer
var image_presentation_timer: Timer

# ==================================================================================================
# 											APP START
# --------------------------------------------------------------------------------------------------

# Called when the node enters the scene tree for the first time.
func _ready():
	# log task start and parameters
	app_start_timestamp = Time.get_unix_time_from_system()
	_log_task("Task open at %s" % str(app_start_timestamp))
	_log_task_parameters()
	# connect button signals
	get_parent().get_node("main_menu/start_button").pressed.connect(_on_start_press)
	get_parent().get_node("inter_block_int/vbox/advance_button").pressed.connect(_on_advance_press)
	# go to menu
	show_menu()

func _log_task_parameters():
	_log_info("Task parameters:")
	_log_info("  block_duration: %d min" % block_duration)
	_log_info("  image_presentation_max_duration: %d s" % image_presentation_max_duration)
	_log_info("  interblock_time: %d s" % interblock_time)
	_log_info("  rsp_freeze_time: %.2f s" % rsp_freeze_time)
	_log_info("  images_folder: '%s'" % images_folder)

# ==================================================================================================
# 									Show and hide Nodes Functions
# --------------------------------------------------------------------------------------------------
func show_menu():
	_log_info("Showing main menu scene")
	# show menu node and activate button
	get_parent().get_node("bg").visible = true
	get_parent().get_node("cf_logo").visible = true
	get_parent().get_node("main_menu/start_button").disabled = false
	get_parent().get_node("main_menu").visible = true
	hide_interblock()
	hide_stimuli()

func hide_menu():
	get_parent().get_node("bg").visible = false
	get_parent().get_node("cf_logo").visible = false
	get_parent().get_node("main_menu/start_button").disabled = true
	get_parent().get_node("main_menu").visible = false
	
func show_interblock():
	# show inter block interval node and activate advance buttons
	_log_info("Showing inter-block interval scene")
	get_parent().get_node("inter_block_int/vbox/advance_button").disabled = false
	get_parent().get_node("inter_block_int").visible = true
	hide_stimuli()
	hide_menu()

func hide_interblock():
	# hide inter block interval node and deactivate advance buttons
	get_parent().get_node("inter_block_int").visible = false
	get_parent().get_node("inter_block_int/vbox/advance_button").disabled = true

func show_stimuli():
	# show stimuli node
	_log_info("Showing stimuli scene")
	visible = true
	$Sprite.visible = true
	hide_interblock()
	hide_menu()

func hide_stimuli():
	# hide stimuli node
	visible = false
	$Sprite.visible = false


# ==================================================================================================
# 										Timer functions
# --------------------------------------------------------------------------------------------------
func start_interblock_timer() -> void:
	# countdown between block 1 (objects) and block 2 (actions)
	_log_info("Starting inter-block timer (%ds)" % interblock_time)
	interblock_timer = Timer.new()
	interblock_timer.wait_time = interblock_time
	interblock_timer.timeout.connect(_on_interblock_timout)
	add_child(interblock_timer)
	interblock_timer.one_shot = true
	interblock_timer.start()

func start_block_timer() -> void:
	# overall time limit for the current block
	_log_info("Starting block timer (%s min)" % str(block_duration))
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
	_rsp_freeze = false
	#_change_image = true

# Timer signals
func _on_interblock_timout():
	_log_info("Inter-block interval finished - starting block 2 (actions)")
	start_block_timer()
	hide_menu()
	hide_interblock()
	#block1 = false
	start_block_images()
	change_texture()
	show_stimuli()

func _on_block_timout():
	_log_info("Block timer expired - ending %s" % ("block 1 (objects)" if block1 else "block 2 (actions)"))
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
	_log_info("No response within %ds - marking trial as failed" % image_presentation_max_duration)
	success = false
	push_answers()
	save(answers)
	change_texture()
# ==================================================================================================
# 											Get Image Paths
# --------------------------------------------------------------------------------------------------
func get_dir_contents(path: String) -> Array:
	# reads a pre-generated manifest.json instead of scanning the folder at runtime -
	# DirAccess can't reliably list imported images in exported builds. Regenerate
	# manifests with tools/generate_stimuli_manifests.py whenever stimuli change.
	var manifest_path = path + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_error("%s No manifest at '%s' - run generate_stimuli_manifests.py" % [INFO_LOG_TAG, manifest_path])
		return []
	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("%s Could not open manifest '%s' (error %d)" % [INFO_LOG_TAG, manifest_path, FileAccess.get_open_error()])
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Array):
		push_error("%s Manifest '%s' is not a JSON array" % [INFO_LOG_TAG, manifest_path])
		return []
	var files: Array = []
	for relative_path in parsed:
		var full_path = path + String(relative_path)
		files.append(full_path)
	_log_info("Loaded %d stimulus file(s) from '%s'" % [files.size(), manifest_path])
	if files.is_empty():
		push_warning("%s Manifest '%s' is empty - check the folder path and difficulty setting." % [INFO_LOG_TAG, manifest_path])
	return files

func start_block_images():
	# point _image_paths at the current block's folder (objects/actions x difficulty)
	var part = "objects" if block1 else "actions"
	var difficulty: int = get_parent().get_node("main_menu/difficulty_hbox/option_button").selected
	difficulty_folder = "%s/%s/%s/" % [images_folder, difficulty, part]
	_log_info("Loading '%s' stimuli (difficulty %d) from '%s'" % [part, difficulty, difficulty_folder])
	_image_paths = get_dir_contents(difficulty_folder)
# ==================================================================================================
# 											Change Images
# --------------------------------------------------------------------------------------------------
func load_texture(path: String) -> void:
	# ResourceLoader (not FileAccess) so imported textures resolve correctly in exported builds -
	# see https://docs.godotengine.org/en/stable/classes/class_resourceloader.html
	if not ResourceLoader.exists(path):
		push_error("%s Resource not found: '%s'" % [INFO_LOG_TAG, path])
		return
	var resource = ResourceLoader.load(path)
	if resource == null or not (resource is Texture2D):
		push_error("%s Failed to load texture: '%s'" % [INFO_LOG_TAG, path])
		return
	$Sprite.texture = resource
	_log_task("Loaded stimulus image: %s" % path)

func _change_texture():
	# pick a random remaining image, show it, arm freeze + timeout
	_rsp_freeze = true
	var random_i = randi() % int(_image_paths.size())
	_figure_path = _image_paths[random_i]
	_image_paths.remove_at(random_i)
	_log_task("Presenting image %s (%d remaining in pool)" % [_figure_path, _image_paths.size()])
	load_texture(_figure_path)
	freeze_change()
	next_image_timer()

func change_texture():
	# advance to next trial, refilling the pool once it's empty
	trial_timestamps = Time.get_ticks_msec()
	if _image_paths.size() != 0:
		_change_texture()
	else:
		_log_task("Image pool exhausted - reloading stimuli for the current block")
		start_block_images()
		_change_texture()
# ==================================================================================================
# 											Save Data
# --------------------------------------------------------------------------------------------------
func save(content) -> void:
	# overwrite this session's JSON log with the full trial history so far
	var fpath = "user://aphasia_stim_registration_%s.json" % [str(task_start_timestamp)]
	var file = FileAccess.open(fpath, FileAccess.WRITE)
	if file == null:
		push_error("%s Could not open '%s' for writing (error %d) - trial data was NOT saved." % [INFO_LOG_TAG, fpath, FileAccess.get_open_error()])
		return
	file.store_line(JSON.stringify(content))
	file.close()
	_log_info("Saved %d trial(s) to %s" % [content["trial_start"].size(), fpath])

func push_answers():
	# append the just-finished trial to answers
	answers["block1"].push_back(block1)
	answers["trial_start"].push_back(trial_timestamps)
	answers["trial_end"].push_back(Time.get_ticks_msec())
	answers["image"].push_back(_figure_path)
	answers["success"].push_back(success)
	_log_info("Trial %d recorded - block: %s, image: %s, success: %s" % [
		answers["image"].size(),
		"objects" if block1 else "actions",
		_figure_path,
		success
	])
# ==================================================================================================
# 											User interaction
# --------------------------------------------------------------------------------------------------
func _on_start_press():
	task_start_timestamp = Time.get_unix_time_from_system()
	_log_task("Task started at unix time %s - beginning block 1 (objects)" % str(task_start_timestamp))
	start_block_timer()
	hide_menu()
	hide_interblock()
	block1 = true
	start_block_images()
	change_texture()
	show_stimuli()

func _on_advance_press():
	_log_info("Inter-block interval finished based on user operation")
	_log_info("Starting block 2 (actions)")
	start_block_timer()
	hide_menu()
	hide_interblock()
	block1 = false
	start_block_images()
	change_texture()
	show_stimuli()

func _input(_event):
	# Esc to Exit Program
	if Input.is_action_pressed("ui_cancel"):
		_log_info("Quit requested (ui_cancel)")
		get_tree().quit()
	if Input.is_action_pressed("ui_accept"):
		if not _rsp_freeze:
			_log_task("Response accepted (ui_accept)")
			success = true
			push_answers()
			save(answers)
			image_presentation_timer.stop()
			change_texture()
	if Input.is_action_pressed("ui_focus_next"):
		_log_info("Manual return to menu (ui_focus_next)")
		image_presentation_timer.stop()
		block_timer.stop()
		hide_interblock()
		hide_stimuli()
		show_menu()
