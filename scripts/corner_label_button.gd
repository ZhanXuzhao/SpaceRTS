extends MarginContainer

## 纯 UI 控件：带 4 个角标和背景色的通用按钮
## 用于技能按钮、生产按钮等

signal pressed
signal right_clicked

var _bg: ColorRect
var _border: ColorRect
var _name_label: Label
var _tl: Label   # top-left     (LabelTL)
var _tr: Label   # top-right    (LabelTR)
var _bl: Label   # bottom-left  (LabelBL)
var _br: Label   # bottom-right (LabelBR)

var _disabled: bool = false


func _ready() -> void:
	_bg = $Bg
	_border = $Border
	_name_label = $Name
	_tl = $LabelTL
	_tr = $LabelTR
	_bl = $LabelBL
	_br = $LabelBR


func _gui_input(event: InputEvent) -> void:
	if _disabled:
		return
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				pressed.emit()
			MOUSE_BUTTON_RIGHT:
				right_clicked.emit()


# ==================== 公开 API ====================

## 背景色
func set_bg_color(c: Color) -> void:
	if _bg == null: _bg = $Bg
	_bg.color = c
func get_bg() -> ColorRect:
	if _bg == null: _bg = $Bg
	return _bg

## 中心文字
func set_name_text(t: String) -> void:
	if _name_label == null: _name_label = $Name
	_name_label.text = t
func get_name_text() -> String:
	if _name_label == null: _name_label = $Name
	return _name_label.text

## 左上角标
func set_tl(t: String) -> void:
	if _tl == null: _tl = $LabelTL
	_tl.text = t
func get_tl() -> Label:
	if _tl == null: _tl = $LabelTL
	return _tl

## 右上角标（技能 CD）
func set_tr(t: String) -> void:
	if _tr == null: _tr = $LabelTR
	_tr.text = t
func get_tr() -> Label:
	if _tr == null: _tr = $LabelTR
	return _tr

## 左下角标
func set_bl(t: String) -> void:
	if _bl == null: _bl = $LabelBL
	_bl.text = t
func get_bl() -> Label:
	if _bl == null: _bl = $LabelBL
	return _bl

## 右下角标（自动标签 / 费用）
func set_br(t: String) -> void:
	if _br == null: _br = $LabelBR
	_br.text = t
func get_br() -> Label:
	if _br == null: _br = $LabelBR
	return _br

## 禁用状态（变灰 + 忽略鼠标）
func set_disabled(val: bool) -> void:
	_disabled = val
	if not is_inside_tree():
		return
	if val:
		modulate = Color(0.4, 0.4, 0.4, 0.6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		modulate = Color(1, 1, 1, 1)
		mouse_filter = Control.MOUSE_FILTER_STOP

func is_disabled() -> bool:
	return _disabled
