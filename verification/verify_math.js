const assert = require('assert');
const fs = require('fs');
const path = require('path');

// Path to the compiled UPL JS file
const uplPath = path.resolve(__dirname, '../target/scala-2.13/upl-fastopt/main.js');

if (!fs.existsSync(uplPath)) {
    console.error("Error: Compiled UPL JS file not found at " + uplPath);
    console.error("Please run 'sbt fastLinkJS' first.");
    process.exit(1);
}

// Mock browser globals
global.window = {};
global.self = global.window;

// Scala.js fastLinkJS output often relies on 'this' being global scope
// In Node.js require(), 'this' is module.exports.
// We can workaround by reading the file and eval-ing it, or by modifying global.
const code = fs.readFileSync(uplPath, 'utf8') + ";\nif (typeof UPL !== 'undefined') global.UPL = UPL;";

// Execute in global scope
(new Function(code)).call(global);

const UPL = global.UPL;

if (!UPL) {
    console.error("Error: UPL global object not found after loading script.");
    process.exit(1);
}

try {
    const mathVerifyPath = path.resolve(__dirname, '../test/serialization_math.p');
    if (!fs.existsSync(mathVerifyPath)) {
        console.error(`Error: Test file ${mathVerifyPath} not found.`);
        process.exit(1);
    }
    const uplCode = fs.readFileSync(mathVerifyPath, 'utf8');

    console.log("Compiling and running UPL code from " + mathVerifyPath + "...");
    // The module is named SerializationMath
    const result = UPL.runToJS(uplCode, "SerializationMath.main");

    console.log("Result (JSON):", JSON.stringify(result, null, 2));

    // Assertions for function serialization
    assert.deepStrictEqual(result.kind, "lambda", "Result should be a lambda");
    assert.strictEqual(result.inputs.length, 1, "Should have 1 input");
    assert.strictEqual(result.inputs[0].name, "x", "Input name should be 'x'");

    // Body should be an application of +
    const body = result.body;
    assert.deepStrictEqual(body.kind, "application", "Body should be an application");
    assert.deepStrictEqual(body.function.kind, "operator", "Function should be an operator");
    assert.strictEqual(body.function.symbol, "+", "Operator should be +");

    assert.strictEqual(body.arguments.length, 2, "Should have 2 arguments");
    assert.deepStrictEqual(body.arguments[0], { kind: "variable", name: "x" }, "First arg is variable x");
    assert.strictEqual(body.arguments[1], 42, "Second arg is 42");

    console.log("Verification PASSED: Function serialized to JSON structure successfully.");

} catch (e) {
    console.error("Verification FAILED:", e);
    process.exit(1);
}
