extends Node

var last_url: String = ""
@export var HandController = preload("res://assets/Config/mano.gd")
var controller

func connect_to_server(url: String):
	last_url = url
	controller.connect_to_server(last_url)
