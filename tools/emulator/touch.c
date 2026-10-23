/* Virtual touchscreen for driving the Sailfish emulator from scripts.
 * Reads commands from stdin:
 *   tap X Y
 *   swipe X1 Y1 X2 Y2 MS
 *   hold X Y MS
 *   sleep MS
 */
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int fd;
static int tracking = 1;

static void emit(int type, int code, int value)
{
    struct input_event ev;
    memset(&ev, 0, sizeof ev);
    ev.type = type;
    ev.code = code;
    ev.value = value;
    if (write(fd, &ev, sizeof ev) < 0)
        perror("write");
}

static void down(int x, int y)
{
    emit(EV_ABS, ABS_MT_SLOT, 0);
    emit(EV_ABS, ABS_MT_TRACKING_ID, tracking++);
    emit(EV_ABS, ABS_MT_POSITION_X, x);
    emit(EV_ABS, ABS_MT_POSITION_Y, y);
    emit(EV_ABS, ABS_MT_TOUCH_MAJOR, 10);
    emit(EV_KEY, BTN_TOUCH, 1);
    emit(EV_ABS, ABS_X, x);
    emit(EV_ABS, ABS_Y, y);
    emit(EV_SYN, SYN_REPORT, 0);
}

static void move(int x, int y)
{
    emit(EV_ABS, ABS_MT_POSITION_X, x);
    emit(EV_ABS, ABS_MT_POSITION_Y, y);
    emit(EV_ABS, ABS_X, x);
    emit(EV_ABS, ABS_Y, y);
    emit(EV_SYN, SYN_REPORT, 0);
}

static void up(void)
{
    emit(EV_ABS, ABS_MT_TRACKING_ID, -1);
    emit(EV_KEY, BTN_TOUCH, 0);
    emit(EV_SYN, SYN_REPORT, 0);
}

int main(int argc, char **argv)
{
    int width = argc > 2 ? atoi(argv[1]) : 720;
    int height = argc > 2 ? atoi(argv[2]) : 1600;
    struct uinput_user_dev dev;
    char line[256];

    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        perror("open /dev/uinput");
        return 1;
    }
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_EVBIT, EV_SYN);
    ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH);
    ioctl(fd, UI_SET_ABSBIT, ABS_X);
    ioctl(fd, UI_SET_ABSBIT, ABS_Y);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_SLOT);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_TRACKING_ID);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_X);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_Y);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_TOUCH_MAJOR);
    ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);

    memset(&dev, 0, sizeof dev);
    snprintf(dev.name, UINPUT_MAX_NAME_SIZE, "e2e-touchscreen");
    dev.id.bustype = BUS_VIRTUAL;
    dev.id.vendor = 0x1;
    dev.id.product = 0x1;
    dev.absmax[ABS_X] = width - 1;
    dev.absmax[ABS_Y] = height - 1;
    dev.absmax[ABS_MT_POSITION_X] = width - 1;
    dev.absmax[ABS_MT_POSITION_Y] = height - 1;
    dev.absmax[ABS_MT_SLOT] = 9;
    dev.absmax[ABS_MT_TRACKING_ID] = 65535;
    dev.absmax[ABS_MT_TOUCH_MAJOR] = 255;
    if (write(fd, &dev, sizeof dev) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("create");
        return 1;
    }
    sleep(2); /* let the compositor pick up the new device */

    while (fgets(line, sizeof line, stdin)) {
        int x1, y1, x2, y2, ms;
        if (sscanf(line, "tap %d %d", &x1, &y1) == 2) {
            down(x1, y1);
            usleep(60000);
            up();
        } else if (sscanf(line, "hold %d %d %d", &x1, &y1, &ms) == 3) {
            down(x1, y1);
            usleep(ms * 1000);
            up();
        } else if (sscanf(line, "swipe %d %d %d %d %d", &x1, &y1, &x2, &y2, &ms) == 5) {
            int steps = ms / 16 > 2 ? ms / 16 : 2;
            down(x1, y1);
            for (int i = 1; i <= steps; i++) {
                usleep(16000);
                move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps);
            }
            usleep(50000);
            up();
        } else if (sscanf(line, "down %d %d", &x1, &y1) == 2) {
            down(x1, y1);
        } else if (sscanf(line, "move %d %d", &x1, &y1) == 2) {
            move(x1, y1);
        } else if (strncmp(line, "up", 2) == 0) {
            up();
        } else if (sscanf(line, "sleep %d", &ms) == 1) {
            usleep(ms * 1000);
        }
        usleep(150000);
    }
    sleep(1);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
