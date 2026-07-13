import uvicorn

from .config import Config
from .server import create_app


def main():
    config = Config()
    uvicorn.run(create_app(config=config), host="127.0.0.1", port=config.port)


if __name__ == "__main__":
    main()
