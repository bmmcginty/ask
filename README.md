# Ask

A command-line interface for interacting with AI language models. Currently supports Anthropic's Claude, with more providers planned.

## Disclaimer

This file has been AI editted and human verified.
No other files in this project have been touched by AI.

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

1. Build the binary:
   ```bash
   crystal build ask.cr
   ```

2. Configure credentials in `~/.creds.yml`:
   ```yaml
   # put keys here for whatever engines you have access to
   claude:
     api_key: "your_api_key_here"
   gemini:
     api_key: "your_api_key_here"
   ```

3. Configure settings in `~/.ask.yml`:
   ```yaml
   default_model: "claude-3-5-sonnet-latest"
   # or "gemini-1.5-pro
   providers:
     claude: {}
     gemini: {}
   ```

## Usage

### Basic Commands

- Start a new conversation: Create a directory and add your question
- Ask a question: Write to `question` file and run `ask`
- View response: Read `answer` file (symlinked to latest response)
- Follow up: Update `question` file and run `ask` again

### File Structure

- Questions are saved as alternating sequential files ending in `q` (e.g., `01q`, `03q`)
- Answers are saved as alternating sequential files ending in `a` (e.g., `02a`, `04a`)
- Latest answer is always symlinked to `answer`

### Attachments

- Lines like <<filename will attach filename to the question.
- These lines are not sent to the AI.
- After use, attachments are copied to the local directory for reuse and later reference.
- Attachments are Xq.bY where X is your question's sequence number and Y is your attachment's sequence number for that question.

### Advanced Features

#### Conversation Management

- **Restart Conversation**: `ask restart`
  - Creates a fresh start while preserving history
  - Previous Q&A won't be sent to AI in future interactions

- **Remove Content**: Delete or move Q&A pairs to exclude them from context

#### Configuration

- **Disable Prompt Caching**: 
  ```bash
  echo "" > .nocache
  ```

- **Change Model**: 
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
- Bug reports
- Feature requests
- New AI provider suggestions (please include a link to API documentation if possible)

## Support

Currently supported providers:
- Anthropic Claude
- Google gemini

More providers planned - open an issue to request support for additional AI models.
