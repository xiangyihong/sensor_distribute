#ifndef BLINKTORADIO_H
#define BLINKTORADIO_H

enum
{
	TIMER_PERIOD_MILLI = 10,
	AM_BLINKTORADIO = 6,
    DATA_SIZE = 50,
};

typedef nx_struct BlinkToRadioMsg
{
	nx_uint16_t nodeid;
	nx_uint16_t counter;
    nx_uint8_t channel;
    nx_uint16_t data[10];
}BlinkToRadioMsg;
#endif
