require('dotenv').config();
const { RunTree } = require("langsmith");

// Set environment variables
process.env.LANGSMITH_TRACING_V2 = "true";
process.env.LANGSMITH_API_URL = "https://api.smith.langchain.com";
process.env.LANGSMITH_PROJECT = "LikeThese";

async function testLangSmith() {
  try {
    console.log("🔄 Starting LangSmith test...");
    
    const apiKey = process.env.LANGSMITH_API_KEY;
    if (!apiKey) {
      throw new Error("LANGSMITH_API_KEY not found in environment");
    }

    // Create parent run
    console.log("🔄 Creating parent run...");
    const parentRun = new RunTree({
      name: "Test Parent Run",
      run_type: "chain",
      inputs: {
        test: true
      },
      serialized: {},
      project_name: "LikeThese",
      apiKey: apiKey,
      apiUrl: process.env.LANGSMITH_API_URL
    });

    await parentRun.postRun();
    console.log("✅ Parent run created successfully");

    // Create a child run
    console.log("🔄 Creating child run...");
    const childRun = await parentRun.createChild({
      name: "Test Child Run",
      run_type: "tool",
      inputs: {
        some_input: "test input"
      }
    });

    await childRun.postRun();
    console.log("✅ Child run posted successfully");

    // End child run with outputs
    await childRun.end({
      outputs: {
        some_output: "test output"
      }
    });
    console.log("✅ Child run completed successfully");

    await childRun.patchRun();

    // End parent run
    await parentRun.end({
      outputs: {
        final_output: "All tests passed"
      }
    });
    console.log("✅ Parent run completed successfully");

    await parentRun.patchRun(false); // false to include child runs

  } catch (error) {
    console.error("❌ Test failed:", {
      error_name: error.name,
      error_message: error.message,
      error_stack: error.stack
    });
  }
}

testLangSmith(); 