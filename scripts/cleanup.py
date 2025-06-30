import logging
import shutil
from pathlib import Path
from typing import List


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
            logging.FileHandler(log_file),  # Logs will also be written to cleanup.log
        ],
    )


def remove_path(path: Path) -> None:
    """
    Removes a file or directory path with proper error handling.

    :param path: The path to remove.
    """
    try:
        if path.is_dir():
            shutil.rmtree(path)
            logging.info(f"Removed directory: {path}")
        elif path.is_file():
            path.unlink()
            logging.info(f"Removed file: {path}")
    except FileNotFoundError:
        logging.warning(f"Path not found (skipped): {path}")
    except Exception as e:
        logging.error(f"Failed to remove {path}: {e}")


def remove_wildcard_paths(parent: Path, pattern: str) -> None:
    """
    Removes files or directories matching a wildcard pattern.

    :param parent: The parent directory containing the wildcard pattern.
    :param pattern: The wildcard pattern to match.
    """
    logging.info(f"Processing wildcard pattern: {pattern} in {parent}")
    for matched in parent.glob(pattern):
        remove_path(matched)


def cleanup_paths(paths: List[Path]) -> None:
    """
    Cleans up specified paths by removing files and directories.

    :param paths: A list of paths to remove.
    """
    for path in paths:
        if "*" in str(path):
            remove_wildcard_paths(path.parent, path.name)
        else:
            remove_path(path)


def cleanup_pycache(root: Path) -> None:
    """
    Removes all __pycache__ directories recursively from the project root.

    :param root: The root directory to search for __pycache__ directories.
    """
    for pycache in root.rglob("__pycache__"):
        remove_path(pycache)


def cleanup() -> None:
    """
    Cleans up the project by removing virtual environments, caches, and build artifacts.
    """
    configure_logging(log_file="cleanup.log")
    project_root = (
        Path(__file__).resolve().parent.parent
    )  # Adjust if scripts directory is elsewhere
    logging.info(f"Project root determined as: {project_root}")

    # Define paths to clean
    paths_to_remove: List[Path] = [
        project_root / ".pytest_cache",
        project_root / ".ruff_cache",
        project_root / ".mypy_cache",
        project_root / "build",
        project_root / "dist",
        project_root / "*.egg-info",
        project_root / ".cache",
    ]

    # Clean specified paths and __pycache__ directories
    cleanup_paths(paths_to_remove)
    cleanup_pycache(project_root)

    logging.info("Cleanup completed successfully!")


if __name__ == "__main__":
    cleanup()
