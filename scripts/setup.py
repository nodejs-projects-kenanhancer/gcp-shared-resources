import logging
import subprocess
import sys


def configure_logging(log_file: str) -> None:
    """
    Configure logging with both console and file handlers.

    :param log_file: Path to the log file.
    """
    logging.basicConfig(
        level=logging.INFO,  # Set the default logging level
        format="%(asctime)s - %(levelname)s - %(message)s",  # Log message format
        handlers=[
            logging.StreamHandler(),  # Logs will be output to the console
            logging.FileHandler(
                log_file
            ),  # Logs will also be written to the specified log file
        ],
    )


def run_command(command: list[str]) -> None:
    """
    Run a shell command and log its execution.

    :param command: The command to execute as a list of strings.
    :raises subprocess.CalledProcessError: If the command fails.
    """
    logging.info(f"Running command: {' '.join(command)}")
    try:
        subprocess.check_call(command)
        logging.info(f"Command completed successfully: {' '.join(command)}")
    except subprocess.CalledProcessError as e:
        logging.error(f"Command failed with error: {e}")
        raise


def setup() -> None:
    """
    Run Poetry install and pre-commit install.
    """
    configure_logging(log_file="setup.log")
    try:
        logging.info("Starting project setup...")
        run_command(["poetry", "install"])  # Install project dependencies with Poetry
        run_command(
            ["poetry", "run", "pre-commit", "install"]
        )  # Install pre-commit hooks
        logging.info("Setup completed successfully!")
    except subprocess.CalledProcessError:
        logging.error("Setup failed. See the log file for details.")
        sys.exit(1)
    except Exception as e:
        logging.exception(f"An unexpected error occurred: {e}")
        sys.exit(1)


if __name__ == "__main__":
    setup()
