#include <Timer.h>
#include "Distribute.h"


#define CL_TEST 0x05

configuration DistributeAppC
{

}

implementation
{
	components MainC, LedsC, DistributeAppC as App;
	components new TimerMilliC() as Timer0;
	components new TimerMilliC() as Timer1;

	components ActiveMessageC();
	components new AMSenderC(AM_BLINKTORADIO);
	components new AMReceiverC(AM_BLINKTORADIO);

	components CC2420ControlC as RssiControl;
	components HplCC2420PinsC as Pins;
    //components GeneralIO;
    //components CC2420Register;

    components new CC2420RssiC() as RssiC;
    components SerialActiveMessageC;
    components CC2420ActiveMessageC;
    components new SerialAMSenderC(CL_TEST);

    components RandomC ;

    App.Random -> RandomC;
    App.SerialControl -> SerialActiveMessageC;
	App.Boot -> MainC.Boot;
	App.Leds -> LedsC;
	App.Timer0 -> Timer0;
	App.Timer1 -> Timer1;
	App.Packet -> AMSenderC;
	App.AMPacket -> AMSenderC;
	App.AMSend -> AMSenderC;
	App.AMControl -> ActiveMessageC;
	App.Receive -> AMReceiverC;
    App.Config -> RssiControl;
    App.RSSI -> RssiC;
    App.UARTSend -> SerialAMSenderC.AMSend;
    App.CSN -> Pins.CSN;
    App.Resource -> RssiC;
    App -> CC2420ActiveMessageC.CC2420Packet;
    App.RadioPacket -> ActiveMessageC;
}
