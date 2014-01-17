Helpers = require './Helpers'

path = require 'path'
fs = require 'fs'
Q = require 'q'
async = require 'async'

class Base


	directory: null

	recursive: false

	excludes: null

	filters: null

	systemFiles: false

	up: false

	findFirst: false

	_async: true

	_data: null


	constructor: (directory) ->
		directory = path.resolve(directory)
		if !fs.statSync(directory).isDirectory()
			throw new Error "Path #{directory} is not directory"

		@directory = directory
		@excludes = []
		@filters = []


	#*******************************************************************************************************************
	#										TESTING
	#*******************************************************************************************************************


	@mock: (tree = {}, info = {}) ->
		FS = require 'fs-mock'
		fs = new FS(tree, info)
		return fs


	@restore: ->
		fs = require 'fs'


	#*******************************************************************************************************************
	#										SETUP
	#*******************************************************************************************************************


	sync: ->
		@_async = false
		return @


	async: ->
		@_async = true
		return @


	recursively: (@recursive = true) ->
		return @


	exclude: (excludes) ->
		if typeof excludes == 'string' then excludes = [excludes]

		result = []
		for exclude in excludes
			result.push(Helpers.normalizePattern(exclude))

		@excludes = @excludes.concat(result)
		return @


	showSystemFiles: (@systemFiles = true) ->
		return @


	lookUp: (@up = true) ->
		return @


	findFirst: (@findFirst = true) ->
		return @


	filter: (fn) ->
		@filters.push(fn)
		return @


	#*******************************************************************************************************************
	#										SEARCHING
	#*******************************************************************************************************************


	getPathsSync: (type = 'all', mask = null, dir = @directory) ->
		paths = []

		try
			read = fs.readdirSync(dir)
		catch err
			if @findFirst == true
				return null

			return paths

		for _path in read
			_path = path.join(dir, _path)

			if !@checkExcludes(_path) || !@checkSystemFiles(_path)
				continue

			try
				stats = fs.statSync(_path)
			catch err
				continue

			switch @checkFile(_path, stats, mask, type)
				when 0
					continue

				when 1
					if @findFirst == true
						return _path

					paths.push(_path)

			if stats.isDirectory() && @recursive == true
				result = @getPathsSync(type, mask, _path)
				if @findFirst == true && typeof result == 'string'
					return result
				else if @findFirst == true && result == null
					continue
				else
					paths = paths.concat(result)

		if @findFirst == true
			return null
		else
			return paths


	getPathsAsync: (fn, type = 'all', mask = null, dir = @directory) ->
		paths = []

		fs.readdir(dir, (err, read) =>
			if err
				fn(if @findFirst == true then null else paths)
			else
				nextPaths = []

				for _path in read
					_path = path.join(dir, _path)

					continue if !@checkExcludes(_path) || !@checkSystemFiles(_path)

					nextPaths.push(_path)

				files = {}
				async.each(nextPaths, (item, cb) ->
					fs.stat(item, (err, stats) ->
						files[item] = stats if !err
						cb()
					)
				, =>
					subDirectories = []
					for file, stats of files
						switch @checkFile(file, stats, mask, type)
							when 0
								continue

							when 1
								if @findFirst == true
									fn(file)
									return null

								paths.push(file)

						if stats.isDirectory() && @recursive == true
							subDirectories.push(file)

					if subDirectories.length == 0
						fn(if @findFirst == true then null else paths)
					else
						async.each(subDirectories, (item, cb) =>
							@getPathsAsync( (result) =>
								if @findFirst == true && typeof result == 'string'
									fn(result)
									cb(new Error 'Fake error')
								else if @findFirst == true && result == null
									cb()
								else
									paths = paths.concat(result)
									cb()
							, type, mask, item)
						, (err) ->
							if !err
								fn(paths)
						)
				)
		)


	#*******************************************************************************************************************
	#										CHECKS
	#*******************************************************************************************************************


	checkExcludes: (_path) ->
		for exclude in @excludes
			if (new RegExp(exclude)).test(_path)
				return false

		return true


	checkSystemFiles: (_path) ->
		if @systemFiles == false
			if path.basename(_path)[0] == '.' || _path.match(/~$/) != null
				return false

		return true


	checkFilters: (_path, stats) ->
		for filter in @filters
			if !filter(stats, _path)
				return false

		return true


	checkFile: (_path, stats, mask, type) ->
		if type == 'all' || (type == 'files' && stats.isFile()) || (type == 'directories' && stats.isDirectory())
			if mask == null || (mask != null && (new RegExp(mask, 'g')).test(_path))
				if !@checkFilters(_path, stats)
					return 0

				return 1

		return 2


	#*******************************************************************************************************************
	#										PARENTS
	#*******************************************************************************************************************


	getPathsFromParentsSync: (mask = null, type = 'all') ->
		directory = @directory
		paths = @getPathsSync(type, mask, directory)

		if @findFirst is on && typeof paths == 'string'
			return paths

		@exclude(directory)

		if @up == true
			depth = directory.match(/\//g).length
		else if typeof @up == 'string'
			if @up == directory
				return if @findFirst is on then null else paths

			match = path.relative(@up, directory).match(/\//g)
			depth = if match == null then 2 else match.length + 2
		else
			depth = @up - 1

		for i in [0..depth - 1]
			directory = path.dirname(directory)
			result = @getPathsSync(type, mask, directory)

			if @findFirst is on && typeof result == 'string'
				return result
			else if @findFirst is on && result == null
				# continue
			else
				paths = paths.concat(result)

			@exclude(directory)

		return if @findFirst is on then null else paths


	getPathsFromParentsAsync: (fn, mask = null, type = 'all') ->
		directory = @directory
		paths = []

		@getPathsAsync( (_paths) =>
			console.log _paths
			paths = _paths

			if @findFirst == true && typeof paths == 'string'
				fn(paths)
			else
				@exclude(directory)

				if @up == true
					depth = directory.match(/\//g).length
				else if typeof @up == 'string'
					if @up == directory
						fn(if @findFirst == true then null else paths)
						return null

					match = path.relative(@up, directory).match(/\//g)
					depth = if match == null then 2 else match.length + 2
				else
					depth = @up - 1

				directories = []
				for i in [0..depth - 1]
					directories.push(path.dirname(directory))
					@exclude(directories[directories.length - 1])

				async.each(directories, (item, cb) =>
					@getPathsAsync( (result) =>
						#console.log item
						#console.log result
						if @findFirst == true && typeof result == 'string'
							fn(result)
							cb(new Error 'Fake error')
						else if @findFirst == true && result == null
							cb()
						else
							paths = paths.concat(result)
							cb()
					, type, mask, item)
				, (err) =>
					if !err
						fn(if @findFirst == true then null else paths)
				)
		, type, mask, directory)


module.exports = Base