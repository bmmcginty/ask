# Ask

A command-line interface for interacting with AI language models. Currently supports Anthropic's Claude, with more providers planned.

## Disclaimer

This file has been AI edited and human verified. No other files in this project have been touched by AI.

## Quick Start

```bash
# Install and setup
crystal build ask.cr

# Create a new conversation
mkdir -p ai/weather
cd ai/weather
echo "Tell me about the hottest place on earth." > question
ask
cat answer
```

## Installation

1.  Build the binary:

    ```bash
    crystal build ask.cr
    ```

2.  Configure credentials in `~/.creds.yml`:

    ```yaml
    # put keys here for whatever engines you have access to
    claude:
      api_key: "your_api_key_here"
    gemini:
      api_key: "your_api_key_here"
    ```

3.  Configure settings in `~/.ask.yml`:

    ```yaml
    default_model: "claude-3-5-sonnet-latest"
    # or "gemini-1.5-pro
    providers:
      claude: {}
      gemini: {}
    ```

## Usage

### Basic Commands

*   Start a new conversation: Create a directory and add your question
*   Ask a question: Write to `question` file and run `ask`
*   View response: Read `answer` file (symlinked to latest response)
*   Follow up: Update `question` file and run `ask` again

### File Structure

*   Questions are saved as alternating sequential files ending in `q` (e.g., `01q`, `03q`)
*   Answers are saved as alternating sequential files ending in `a` (e.g., `02a`, `04a`)
*   Latest answer is always symlinked to `answer`

### Attachments

*   Lines like ``<<filename`` will attach filename to the question. `filename` can be absolute, or relative to the current directory.
*   These lines are not sent to the AI.
*   After the first successful use, attachments are copied to the current directory for reuse and later reference.
*   Attachments are named `Xq.bY` where `X` is your question's sequence number and `Y` is your attachment's sequence number for that question.

### Advanced Features

#### Model Aliases

You can define aliases for models in your `~/.ask.yml` file:

```yaml
providers:
  anthropic:
    models:
      claude-3-7-sonnet-latest:
        - s37
  google:
    models:
      gemini-2.5-pro-exp-03-25:
        - g25
```

Then, within a conversation directory, setting `.model` to `s37` will use `claude-3-7-sonnet-latest` and `g25` will use `gemini-2.5-pro-exp-03-25`. For example:

```bash
echo "s37" > .model
ask
```

### Tool Calling

`ask` allows you to use external tools and incorporate their results into the conversation. All tool runs are logged in `~/.ask/logs/<name>/<date>/<time>`. See `sample-tools` for examples.

1.  **Tool Directory:** Place your executable tools in the `~/.ask/tools` directory. Each tool in `~/.ask/tools` must be in its own directory.

    Each tool directory must include:

    *   `exe`: The tool itself. Permissions must include `u+x`. Reads JSON from standard input and writes JSON to standard output.
    *   `description`: A plain text file describing the tool's inputs, outputs, and purpose. Sent to the AI as documentation.
    *   `schema`: A JSON schema describing the tool's inputs.
    *   `provider`: A file containing either a single asterisk or the name of a provider. Needed for future work on provider-provided internal tools.

2.  **List Tools:** Use `ask tool` to see a list of available tools detected in the `~/.ask/tools` directory.

3.  **Enable Tool:** To enable a tool for the current conversation, use the `ask tool enable <tool_name>` command within the conversation directory. For example:

    ```bash
    cd ai/weather # or wherever you are working
    ask tool enable add
    ```

4.  **Using Enabled Tools:** When the AI determines that a tool needs to be used, it will request its use. You will be prompted with the tool name and arguments proposed by the AI. For example:

    ```bash
    echo "What is 4 + 4?" > question
    ask
    ```

    `ask` will output something like:

    ```text
    add {"a": 4, "b": 4}
    ```

    Press `<enter>` to run the tool or `ctrl-c` to exit. For brevity, no prompt is displayed.

    *   **Security Note:** Each tool execution requires manual approval for security reasons, preventing potentially harmful or unintended actions.

5.  **Tool Output:** If approved, the tool's output will be sent back to the AI, and the conversation will continue. This cycle will repeat as needed until:

    *   The AI no longer requests tool use.
    *   The user ends the conversation.
    *   The user aborts the session by pressing `<ctrl-c>` at the tool request prompt.

#### Conversation Management

*   **Restart Conversation**: `ask restart`
    *   Creates a fresh start while preserving history
    *   Previous Q&A won't be sent to AI in future interactions

*   **Remove Content**: Delete or move Q&A pairs to exclude them from context

#### Configuration

*   **Disable Prompt Caching**:

    ```bash
    echo "" > .nocache
    ```

*   **Change Model**:

    ```bash
    echo "model-name" > .model
    ```

### Extended Example

```bash
# Start conversation about weather
mkdir -p ai/weather
cd ai/weather
echo "What is the coldest city on earth?" > question
ask
cat answer

# Follow up
echo "Tell me more about the place(s) you mentioned above." > question
ask

# Start new topic
ask restart
echo "Tell me how to cook pasta." > question
ask

# Organize conversations
mkdir ../cooking
mv 03q 04a ../cooking/

# Re-enable full history
rm .restart

# Continue previous conversation
echo "Tell me even more about the above places." > question
ask

# ask about an image from the web
mkdir ../web-img
cd web-img
wget "https://example.com/image.png"
echo '<<image.png' > question
echo "Describe this image." >> question
ask
```

## Contributing

Feel free to open issues for:

*   Bug reports
*   Feature requests
*   New AI provider suggestions (please include a link to API documentation if possible)

## Support

Currently supported providers:

*   Anthropic Claude
*   Google Gemini

More providers planned - open an issue to request support for additional AI models.
