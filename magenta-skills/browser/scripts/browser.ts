import puppeteer, { Page } from 'puppeteer';
import * as fs from 'fs';
import * as path from 'path';

interface Command {
  type: string;
  args: string[];
  code?: string; // For eval command
}

function parseCommands(script: string): Command[] {
  const lines = script.split('\n');
  const commands: Command[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i].trim();

    // Skip empty lines and comments
    if (!line || line.startsWith('#')) {
      i++;
      continue;
    }

    // Check for eval block
    if (line === 'eval') {
      const codeLines: string[] = [];
      i++;

      while (i < lines.length && lines[i].trim() !== 'endeval') {
        codeLines.push(lines[i]);
        i++;
      }

      if (i >= lines.length) {
        throw new Error('eval block not closed with endeval');
      }

      commands.push({
        type: 'eval',
        args: [],
        code: codeLines.join('\n')
      });
      i++; // Skip the endeval line
      continue;
    }

    // Parse regular command: commandName arg1 arg2 ...
    const parts = line.split(/\s+/);
    const type = parts[0];
    const args = parts.slice(1);

    // Join all args back together as a single string for most commands
    // This allows selectors and URLs to have spaces if needed
    const fullArg = args.join(' ');

    commands.push({
      type,
      args: fullArg ? [fullArg] : []
    });

    i++;
  }

  return commands;
}

async function executeCommand(command: Command, page: Page, state: { keepOpen: boolean }): Promise<void> {
  const { type, args, code } = command;

  switch (type) {
    case 'eval':
      if (!code) {
        throw new Error('eval command requires code block');
      }
      console.log('Evaluating code in page context...');

      // Capture console output from the page
      const consoleMessages: string[] = [];
      const consoleHandler = (msg: any) => {
        const type = msg.type();
        const text = msg.text();
        consoleMessages.push(`[browser ${type}] ${text}`);
      };

      page.on('console', consoleHandler);

      try {
        // Wrap code in an async function to support return statements
        const wrappedCode = `(async () => { ${code} })()`;
        const result = await page.evaluate(wrappedCode);

        // Output any console messages from the browser
        if (consoleMessages.length > 0) {
          console.log('\nBrowser console output:');
          consoleMessages.forEach(msg => console.log(msg));
        }

        // Always output the result
        console.log('\nEval result:', result);
      } finally {
        page.off('console', consoleHandler);
      }
      break;

    case 'load':
      if (args.length !== 1) {
        throw new Error(`load expects 1 argument, got ${args.length}`);
      }
      console.log(`Loading ${args[0]}...`);
      await page.goto(args[0], { waitUntil: 'networkidle2' });
      break;

    case 'waitForElement':
      if (args.length !== 1) {
        throw new Error(`waitForElement expects 1 argument, got ${args.length}`);
      }
      console.log(`Waiting for element ${args[0]}...`);
      await page.waitForSelector(args[0], { timeout: 30000 });
      break;

    case 'click':
      if (args.length !== 1) {
        throw new Error(`click expects 1 argument, got ${args.length}`);
      }
      console.log(`Clicking ${args[0]}...`);
      await page.click(args[0]);
      break;

    case 'type':
      if (args.length !== 1) {
        throw new Error(`type expects 1 argument, got ${args.length}`);
      }
      console.log(`Typing "${args[0]}"...`);
      await page.keyboard.type(args[0]);
      break;

    case 'waitForNewPage':
      if (args.length !== 1) {
        throw new Error(`waitForNewPage expects 1 argument, got ${args.length}`);
      }
      console.log(`Waiting for navigation to ${args[0]}...`);
      await page.waitForNavigation({ waitUntil: 'networkidle2' });
      const currentUrl = page.url();
      if (!currentUrl.includes(args[0])) {
        console.warn(`Warning: Expected URL to contain ${args[0]}, but got ${currentUrl}`);
      }
      break;

    case 'screenshot':
      if (args.length !== 1) {
        throw new Error(`screenshot expects 1 argument, got ${args.length}`);
      }
      const screenshotDir = '/tmp/magenta';
      const screenshotPath = path.join(screenshotDir, args[0]);

      // Ensure directory exists
      if (!fs.existsSync(screenshotDir)) {
        fs.mkdirSync(screenshotDir, { recursive: true });
      }

      console.log(`Taking screenshot ${screenshotPath}...`);
      await page.screenshot({ path: screenshotPath as `${string}.png` | `${string}.jpeg` | `${string}.webp` });
      break;

    case 'sleep':
      if (args.length !== 1) {
        throw new Error(`sleep expects 1 argument, got ${args.length}`);
      }
      const ms = parseInt(args[0], 10);
      if (isNaN(ms)) {
        throw new Error(`sleep argument must be a number, got ${args[0]}`);
      }
      console.log(`Sleeping for ${ms}ms...`);
      await new Promise(resolve => setTimeout(resolve, ms));
      break;

    case 'hover':
      if (args.length !== 1) {
        throw new Error(`hover expects 1 argument, got ${args.length}`);
      }
      console.log(`Hovering over ${args[0]}...`);
      await page.hover(args[0]);
      break;

    case 'select':
      // Split args for multi-argument commands
      const selectArgs = args[0].split(/\s+/, 2);
      if (selectArgs.length !== 2) {
        throw new Error(`select expects 2 arguments (selector value), got ${selectArgs.length}`);
      }
      console.log(`Selecting "${selectArgs[1]}" in ${selectArgs[0]}...`);
      await page.select(selectArgs[0], selectArgs[1]);
      break;

    case 'focus':
      if (args.length !== 1) {
        throw new Error(`focus expects 1 argument, got ${args.length}`);
      }
      console.log(`Focusing ${args[0]}...`);
      await page.focus(args[0]);
      break;

    case 'pressKey':
      if (args.length !== 1) {
        throw new Error(`pressKey expects 1 argument, got ${args.length}`);
      }
      console.log(`Pressing key "${args[0]}"...`);
      await page.keyboard.press(args[0] as any);
      break;

    case 'getText':
      if (args.length !== 1) {
        throw new Error(`getText expects 1 argument, got ${args.length}`);
      }
      console.log(`Getting text from ${args[0]}...`);
      const text = await page.$eval(args[0], el => el.textContent || '');
      console.log(`Text content: ${text}`);
      break;

    case 'getAttribute':
      // Split args for multi-argument commands
      const attrArgs = args[0].split(/\s+/, 2);
      if (attrArgs.length !== 2) {
        throw new Error(`getAttribute expects 2 arguments (selector attribute), got ${attrArgs.length}`);
      }
      console.log(`Getting attribute "${attrArgs[1]}" from ${attrArgs[0]}...`);
      const attrValue = await page.$eval(attrArgs[0], (el, attr) => el.getAttribute(attr), attrArgs[1]);
      console.log(`Attribute value: ${attrValue}`);
      break;

    case 'reload':
      if (args.length !== 0) {
        throw new Error(`reload expects 0 arguments, got ${args.length}`);
      }
      console.log(`Reloading page...`);
      await page.reload({ waitUntil: 'networkidle2' });
      break;

    case 'saveContent':
      if (args.length !== 1) {
        throw new Error(`saveContent expects 1 argument, got ${args.length}`);
      }
      const contentDir = '/tmp/magenta';
      const contentPath = path.join(contentDir, args[0]);

      // Ensure directory exists
      if (!fs.existsSync(contentDir)) {
        fs.mkdirSync(contentDir, { recursive: true });
      }

      console.log(`Saving page content to ${contentPath}...`);
      const htmlContent = await page.content();
      fs.writeFileSync(contentPath, htmlContent, 'utf-8');
      break;

    case 'keepOpen':
      if (args.length !== 0) {
        throw new Error(`keepOpen expects 0 arguments, got ${args.length}`);
      }
      console.log('Browser will remain open after script completes...');
      state.keepOpen = true;
      break;

    default:
      throw new Error(`Unknown command: ${type}`);
  }
}

async function runScript(script: string): Promise<void> {
  const browser = await puppeteer.launch({
    headless: false,
    defaultViewport: { width: 1280, height: 720 }
  });

  const state = { keepOpen: false };

  try {
    const page = await browser.newPage();
    const commands = parseCommands(script);

    for (const command of commands) {
      try {
        await executeCommand(command, page, state);
      } catch (error) {
        console.error(`Error executing command: ${command.type}`);
        throw error;
      }
    }

    console.log('Script completed successfully!');
  } finally {
    if (!state.keepOpen) {
      await browser.close();
    } else {
      console.log('Browser kept open. Close manually when done.');
    }
  }
}

// Main execution
const script = process.argv[2];
if (!script) {
  console.error('Usage: tsx browser.ts "command1()\\ncommand2()"');
  process.exit(1);
}

runScript(script).catch(error => {
  console.error('Script failed:', error);
  process.exit(1);
});
