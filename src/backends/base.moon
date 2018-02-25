backends = {}

class Backend
	new: =>
		@name = "No backend"

	encode: (params, detached) =>
		msg.verbose("Building command from params: ", utils.to_string(params))
		command = self\buildCommand(params)
		if command
			msg.info("Encoding to", params.outputPath)
			msg.verbose("Command line:", table.concat(command, " "))
			if detached
				utils.subprocess_detached({args: command})
				return true
			return run_subprocess({args: command, cancellable: false})
		return false

	buildCommand: (params) => nil
