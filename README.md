# Ask

A command-line interface for interacting with AI language models. Currently supports Anthropic's Claude, with more providers planned.

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
   claude:
     api_key: "your_api_key_here"
   ```

3. Configure settings in `~/.ask.yml`:
   ```yaml
   default_model: "claude-3-5-sonnet-latest"
   providers:
     claude: {}
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
```

## Contributing

Feel free to open issues for:
- Bug reports
- Feature requests
- New AI provider suggestions (please include a link to API documentation if possible)

## Support

Currently supported providers:
- Anthropic Claude

More providers planned - open an issue to request support for additional AI models.
