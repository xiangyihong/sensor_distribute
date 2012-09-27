#ifndef DISTRIBUTE_H_
#define DISTRIBUTE_H_


enum
{
	//
	TIMER_PERIOD_MILLI = 10,
	
	AM_BLINKTORADIO = 6,
	DATA_SIZE = 50,


};

//prr-sinr points needed by every node
#define	PRR_SINR_POINTS 4

	//the number of nodes except the sink
#define	NUM_OF_NODES  9

	//the position of the sink command
#define COMMAND_POSITION 2
	//the position the node id which the sink has a command for
#define NODE_ID_POSITION  3


//commads sent by the sink	
	#define START_BEGIN  1
	#define PERIOD_BEGIN  2
	#define PERIOD_END  3
	#define END_ALL  4
	#define IN_PERIOD  5
	#define MEASURE_RSSI  6
	#define COMMAND_REPORT_POINTS 7
	#define REPORT_POINTS 8
	#define REPORT_PRR 9

typedef nx_struct Distribute 
{
	nx_uint16_t nodeid;
	nx_uint16_t counter;
	nx_uint16_t data[10];
}DistributeMsg;
#endif