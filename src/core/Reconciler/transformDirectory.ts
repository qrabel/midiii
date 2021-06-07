/*
 * File: transformDirectory.ts
 * File Created: Friday, 4th June 2021 12:36:38 am
 * Author: richard
 * Description: Turns a folder directory into a Roblox instance.
 */

import Make from "packages/make";
import { HttpService } from "packages/services";
import { Directory, File } from "utils/filesystem";
import transformFile from "./transformFile";

/** A list of file names that should not become files. */
const RESERVED_NAMES = new ReadonlySet<string>(["init.lua", "init.server.lua", "init.client.lua", "init.meta.json"]);

/** Interface for `init.meta.json` data. */
interface InstanceMetadata<T extends keyof CreatableInstances> {
	className?: T;
	properties?: Map<keyof WritableInstanceProperties<CreatableInstances[T]>, never>;
}

/**
 * Creates an instance from the given metadata.
 * @param metadata The init.meta.json data.
 * @param name The name of the instance.
 * @returns A new instance.
 */
function makeFromMetadata(metadata: InstanceMetadata<keyof CreatableInstances>, name: string) {
	// Create the instance first to ensure 'className' is always
	// prioritized, even if there are no properties set.
	const instance = Make(metadata.className || "Folder", { Name: name });

	// Currently, only primitive types can be defined.
	if (metadata.properties) for (const [key, value] of metadata.properties) instance[key] = value;

	return instance;
}

/**
 * Creates an Instance for the given folder.
 * [Some files](https://rojo.space/docs/6.x/sync-details/#scripts) can modify the class and properties during creation.
 * @param dir The directory to make an Instance from.
 * @param parent Optional parent of the Instance.
 * @returns THe instance created for the folder.
 */
function transformDirectory(dir: Directory, scope: number): Instance {
	let instance: Instance | undefined;

	// Check if the directory contains a special init file.
	// https://rojo.space/docs/6.x/sync-details/#scripts
	// https://rojo.space/docs/6.x/sync-details/#meta-files
	const init = dir.locateFiles("init.lua", "init.server.lua", "init.client.lua", "init.meta.json");

	// Turns the directory into a script instance using the init file.
	if (init?.extension === "lua") instance = transformFile(init, scope, dir.name);
	// Turns the directory into an instance using the metadata.
	else if (init?.extension === "json")
		instance = makeFromMetadata(HttpService.JSONDecode(readfile(init.location)), dir.name);
	// Nothing is special about this directory! Make a normal folder.
	else instance = Make("Folder", { Name: dir.name });

	// Scan the file to descend the instance tree.
	for (const f of listfiles(dir.location)) {
		const fileName = f.match("([^/]+)$")[0] as string;

		// Make sure the file is not reserved for special use
		if (RESERVED_NAMES.has(fileName)) continue;

		if (isfile(f)) {
			const obj = transformFile(File(f, dir.origin), scope);
			if (obj) obj.Parent = instance;
		} else transformDirectory(Directory(f, dir.origin), scope).Parent = instance;
	}

	// An instance definitely exists! if there is no special file present, the
	// folder is made (see 'else' condition above).
	return instance!;
}

export = transformDirectory;