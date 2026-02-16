const fs = require('fs');
const path = require('path');

// Locate the compiled JS file
// sbt fastLinkJS output location: target/scala-2.13/upl-fastopt/main.js
let uplPath = path.resolve(__dirname, '../target/scala-2.13/upl-fastopt/main.js');

if (!fs.existsSync(uplPath)) {
    // Try looking in vscode extension source if built there
    uplPath = path.resolve(__dirname, '../vscode-extension/extension/src/main.js');
}

if (!fs.existsSync(uplPath)) {
    console.error("Could not find compiled UPL JS file at: " + uplPath);
    process.exit(1);
}

// Mock browser/DOM globals if needed by Scala.js output
// (Scala.js often needs `window`, `self`, or `global` setup depending on ModuleKind)
global.window = global;
global.self = global;

console.log(`Loading UPL from ${uplPath}...`);

// Scala.js fastLinkJS output often relies on 'this' being global scope
// In Node.js require(), 'this' is module.exports.
// We can workaround by reading the file and eval-ing it, or by modifying global.
const code = fs.readFileSync(uplPath, 'utf8') + ";\nif (typeof UPL !== 'undefined') global.UPL = UPL;";

// Execute in global scope
// This is a bit hacky but standard for loading Scala.js fastOpt in Node without CommonJS module settings
(new Function(code)).call(global);

// UPL should now be in global
const UPL = global.UPL;

if (!UPL) {
    console.error("UPL object not found in global scope after loading.");
    // Try checking if it attached to module.exports just in case
    if (typeof exports !== 'undefined' && exports.UPL) {
        console.log("Found UPL in exports.");
        UPL = exports.UPL;
    } else {
        process.exit(1);
    }
}

if (typeof UPL.runToJS !== 'function') {
    console.error("UPL.runToJS is not a function. Serialization implementation might differ.");
    console.log("Available keys on UPL:", Object.keys(UPL));
    process.exit(1);
}

const testFile = path.resolve(__dirname, '../test/serialization_verify.p');
const input = fs.readFileSync(testFile, 'utf8');

console.log("Running UPL.runToJS...");
try {
    const result = UPL.runToJS(input, "SerializationVerify.main");
    console.log("Result type:", typeof result);
    console.log("Result value:", JSON.stringify(result, null, 2));

    // Simple assertion
    // Expected: [1, "hello", true, [10, 20, 30], [42, "nested"]]
    // Note: Tuples map to Arrays in our impl

    const expected = [1, "hello", true, [10, 20, 30], [42, "nested"]];
    if (JSON.stringify(result) === JSON.stringify(expected)) {
        console.log("SUCCESS: Output matches expected JSON structure.");
    } else {
        console.error("FAILURE: Output does not match expected JSON structure.");
        console.error("Expected:", JSON.stringify(expected));
        process.exit(1);
    }

} catch (e) {
    console.error("Error running UPL:", e);
    process.exit(1);
}
