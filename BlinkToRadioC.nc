#include <Timer.h>
#include "BlinkToRadio.h"
#define MAX_PKG 1000
module BlinkToRadioC
{
    uses interface Boot;
    uses interface Leds;
    uses interface Timer<TMilli> as Timer0;
    uses interface Packet;
    uses interface AMPacket;
    uses interface AMSend;
    uses interface SplitControl as AMControl;
    uses interface SplitControl as SerialControl;
    uses interface Receive;
    uses interface CC2420Config as Config;
    uses interface CC2420Packet;
    uses interface Resource;
    uses interface GeneralIO as CSN;
    uses interface CC2420Register as RSSI;
    uses interface AMSend as UARTSend;
    uses interface Packet as RadioPacket;
}
implementation
{
    uint16_t counter = 0;
    uint16_t i = 0;
    uint16_t tmprssi = 0;
    uint8_t power = 23;
    bool busy = FALSE;
    bool UARTBusy = FALSE;
    message_t pkt;
    uint16_t n = 0;
    uint16_t pre_power = 0;
    event void Boot.booted()
    {
        call SerialControl.start();
    }

    event void SerialControl.startDone(error_t err)
    {
        if(err != SUCCESS)
        {
            call SerialControl.start();
        }
        else
        {
            call AMControl.start();
        }
    }

    event void SerialControl.stopDone(error_t err)
    {
    }

    event void AMControl.startDone(error_t err)
    {
        if(err == SUCCESS)
        {
            BlinkToRadioMsg* btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(&pkt, sizeof(BlinkToRadioMsg)));
            btrpkt->nodeid = 255;
            call Timer0.startPeriodic(TIMER_PERIOD_MILLI);
            if(TOS_NODE_ID == 1)
            {
                //call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BlinkToRadioMsg)) ;
            }
            call Leds.led0Toggle();
            pre_power = (uint16_t)power;
        }
        else
        {
            call AMControl.start();
        }
    }
    event void AMControl.stopDone(error_t err)
    {
    }

    event void Timer0.fired()
    {
        uint8_t j;
        counter++;
        //node id 1 is the sink node,which need not to send pkg
        if(TOS_NODE_ID != 1) 
        {
            if(!busy)
            {
                BlinkToRadioMsg* btrpkt = (BlinkToRadioMsg*)
                    (call Packet.getPayload(&pkt,sizeof(BlinkToRadioMsg)));
                btrpkt->nodeid = TOS_NODE_ID;
                btrpkt->counter = counter;
                btrpkt->channel = call Config.getChannel();
                for(j = 0 ; j < 10 ; ++j)
                {
                    btrpkt->data[j] = i+counter;
                    i++;
                }
                call CC2420Packet.setPower(&pkt,power);
                btrpkt->data[2] = call CC2420Packet.getPower(&pkt);
                if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BlinkToRadioMsg)) == SUCCESS)
                {
                    busy = TRUE;
                }

            }
        }
    }

    event void AMSend.sendDone(message_t* msg, error_t error)
    {
        if(&pkt == msg)
        {
            busy = FALSE;
            call Leds.led2Toggle();
            if(TOS_NODE_ID == 2)
            {
                n++;
                if(n == MAX_PKG)
                {
                    n = 0;
                    power--;
                }
            }
        }
    }
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
    {
        uint16_t rssi;
        uint8_t x;
        uint16_t tmpID;
        BlinkToRadioMsg* btrpkt;
        call Leds.led0Toggle();
        if(TOS_NODE_ID != 1)
        {
            /*btrpkt = (BlinkToRadioMsg*)payload;
              if(btrpkt->nodeid == 255)
              {
              if(power != 0)
              {
              power--;
              }
              }*/
        }
        else
        {
            rssi = call CC2420Packet.getRssi(msg);
            rssi = rssi & 0x00ff;
            if(len == sizeof(BlinkToRadioMsg))
            {
                call Leds.led1Toggle();
                btrpkt = (BlinkToRadioMsg*)payload;
                btrpkt->data[0] = rssi;
                call Resource.request();
                //while(tmprssi == 0);
                for(x = 0 ; x < 255 ; ++x)
                {

                }
                btrpkt->data[1] = tmprssi;
                atomic
                {
                    tmprssi = 0;
                }
                if(pre_power != btrpkt->data[2])
                {
                    tmpID = btrpkt->nodeid;
                    btrpkt->nodeid = 255;
                    if(!UARTBusy)
                    {
                        if(call UARTSend.send(0xffff,msg,call RadioPacket.payloadLength(msg)) == SUCCESS)
                        {
                            UARTBusy = TRUE;
                        }
                    }
                }
                pre_power = btrpkt->data[2];
                if(!UARTBusy)
                {
                    if( call UARTSend.send(0xffff,msg, call RadioPacket.payloadLength(msg)) == SUCCESS)
                    {
                        UARTBusy = TRUE;
                    }
                }
                /*n++;
                  if(n == MAX_PKG)
                  {
                  n = 0;
                  btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(&pkt, sizeof(BlinkToRadioMsg)));
                  btrpkt->nodeid = 255;
                  if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BlinkToRadioMsg ))== SUCCESS) 
                  {
                  busy = TRUE;
                  }
                  }*/
            }
        }
        return msg;
    }

    event void UARTSend.sendDone(message_t* msg, error_t err)
    {
        UARTBusy = FALSE;
    }
    event void Resource.granted()
    {
        call CSN.clr();
        atomic
        {
            call RSSI.read(&tmprssi);
        }
        call CSN.set();
        call Resource.release();
        tmprssi = tmprssi & 0x00ff;
    }

    event void Config.syncDone(error_t err){}
}

