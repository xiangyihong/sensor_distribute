#include <Timer.h>
#include "Distribute.h"

#define MAX_PKG 500
#define MAX_POWER 31
#define NORMAL_POWER 4
#define MIN_SINR 0
#define MAX_SINR 5
#define MAX_PERIOD 100
#define MAX_NODE_ID (1+NUM_OF_NODES)

module DistributeAppC
{
  uses interface Boot;
  uses interface Leds;
  uses interface Timer<TMilli> as Timer0;
  uses interface Timer<TMilli> as Timer1;
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
  uses interface Random;
}


//TODO
/*
   the function that sink sends a packet to start a period
   the movement 
 */
implementation
{
  uint16_t counter = 0;
  bool busy = FALSE;
  bool UARTBusy = FALSE;
  bool MeasureRssiBusy = FALSE;
  bool sendBusy = FALSE;
  message_t pkg;

  uint16_t num_of_period = 0;
  //被普通节点用来区分是发送剩余点数还是发送prr
  bool end_all = FALSE;

  uint16_t rssi_of_neighbour[NUM_OF_NODES];
  uint16_t period_times = 0;
  uint16_t remainning_points = 0;
  uint16_t remainning_points_of_neighbour = 0;
   uint16_t remain_points_for_sink = 0;

  //过渡区间为0-4
  bool prr_sinr[5];
  uint16_t received_packet[5];
  //记录prr
  //float prr[5];

  bool has_choose_trans = FALSE;
  uint16_t chosen_trans_id;
  uint16_t sinr_in_period ;

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

  event void AMControl.startdone(error_t err)
  {
    uint8_t i;
    if(err == SUCCESS)
    {
      //if start ok, then light the red led.
      call Leds.led0Toggle();

      //随机数初始化
      call Random.init();
      
      if(TOS_NODE_ID == 1)
      {

        //the sink would ask every node to send one packet so that the other nodes would record the 
        //rssi of the packet
        i = 2;
        while(i < (2+NUM_OF_NODES) && !MeasureRssiBusy)
        {
          if(!busy)
          {
            //set a timer which fired every 20ms.
            //this timer is used for nodes in the wsn to send one packet so that the other nodes 
            //would record its rssi. I am sure that 20ms would be enough for the node to send a packet.
            //i use the magic number here because i may change the interval of the timer
            //and i want the interval be the same with the comment
            MeasureRssiBusy = TRUE; 
            call Timer0.start(20);

            //fulfill the message sent by the sink
            DistributeMsg* dmpkt = (DistributeMsg*)(call Packet.getPayload(&pkg, sizeof(DistributeMsg)));
            dmpkt->nodeid = TOS_NODE_ID;
            dmpkt->counter = 0;
            dmpkt->data[COMMAND_POSITION] = START_BEGIN;
            dmpkt->data[NODE_ID_POSITION] = i;

            reportToComputer(&pkg);

            if(call AMSend.send(AM_BROADCAST_ADDR, &pkg, sizeof(DistributeMsg)) == SUCCESS)
            {
              busy = TRUE;

            }
            i++;
          }
        }
        //各个点都发完包后，进入第一个period
        sinkStartPeriod();

      }
      else
      {
        i = 0;
        for(i = 0 ; i < NUM_OF_NODES; ++i)
        {
          rssi_of_neighbour[i] = 255;
        }
        for(i = 0 ; i < 5 ; ++i)
        {
          prr_sinr[i] = FALSE;
          received_packet[i] = 0;
        }
      }
    }
    else
    {
      call AMControl.start();
    }
  }

  //if send successfully, light the green led.
  event void AMSend.sendDone(message_t* msg, error_t error)
  {
    if(&pkg == msg)
    {
      busy = FALSE;
      call Leds.led2Toggle();
    }
  }

  event void Timer0.fired()
  {
    MeasureRssiBusy = FALSE;
    sendBusy = FALSE;
  }

  //timer1 fired, which means the end of a period for sink
  //for the other nodes, it means that it should report the remainning points to the sink
  event void Timer1.fired()
  {
    uint16_t i;
    DistributeMsg* dmpkt = (DistributeMsg*)(call Packet.getPayload(&pkg, sizeof(DistributeMsg)));
    dmpkt->nodeid = TOS_NODE_ID;
    dmpkt->counter = 0;

    if(TOS_NODE_ID == 1)
    {
      dmpkt->data[COMMAND_POSITION] = PERIOD_END;
      reportToComputer(&pkg);
    }
    else
    {
        call CC2420Packet.setPower(&pkg,MAX_POWER);
        dmpkt->data[4] = call CC2420Packet.getPower(&pkg);

        if( !end_all)
        {
          dmpkt->data[COMMAND_POSITION] = REPORT_POINTS;
        }
        else
        {
            dmpkt->data[COMMAND_POSITION] = REPORT_PRR;
            //data的后五个存储接受到的包数
            for(i = 0 ; i < 5; ++i)
            {
                dmpkt->[i+5] = received_packet[i];
            }
        }
    }


    if( call AMSend(AM_BROADCAST_ADDR, &pkg, sizeof(DistributeMsg)) == SUCCESS)
    {
      busy = TRUE;
    }
  }

  event void AMControl.stopDone(error_t err)
  {
  }

  //process the message the node received
  //It's the core of this program

  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
  {
    uint16_t id;
    uint16_t com; //command

    id = (DistributeMsg*)payload->nodeid;
    com = (DistributeMsg*)payload->data[COMMAND_POSITION];

    call Leds.led1Toggle();

    if(TOS_NODE_ID != 1)
    {
      uint16_t rssi;
      bool take_part_in_period;
      uint16_t sinr;
      uint16_t i;

      DistributeMsg* dmpkt = (DistributeMsg*)(call Packet.getPayload(&pkg, sizeof(DistributeMsg)));

      switch(com)
      {
        //the sink ask this node to send one packet
        case START_BEGIN:
          if(TOS_NODE_ID == dmpkt->data[NODE_ID_POSITION])
          {
            dmpkt->nodeid = TOS_NODE_ID;
            dmpkt->data[COMMAND_POSITION] = MEASURE_RSSI;
            dmpkt->counter = 0;
            call CC2420Packet.setPower(&pkg,NORMAL_POWER);

            if( call AMSend(AM_BROADCAST_ADDR, &pkg, sizeof(DistributeMsg)) == SUCCESS)
            {
              busy = TRUE;
            }
          }
          break;

          //the node receives a packet that is used for recording rssi
        case MEASURE_RSSI:
          rssi = getRssi(msg);

          rssi_of_neighbour[id - 2] = rssi;
          remainning_points_of_neighbour += PRR_SINR_POINTS;
          break;

        case PERIOD_BEGIN:
          take_part_in_period = takePart(remainning_points_of_neighbour);          
          if(take_part_in_period)
          {
            //节点选择在此period发包
            i = 1;
            while(i <= MAX_PKG && !sendBusy)
            {
              if(!busy)
              {

                sendBusy = TRUE; 
                call Timer0.start(TIMER_PERIOD_MILLI);

                //fulfill the message sent by the sink
                dmpkt->nodeid = TOS_NODE_ID;
                dmpkt->counter = i;
                dmpkt->data[COMMAND_POSITION] = IN_PERIOD;
                call CC2420Packet.setPower(&pkg,NORMAL_POWER);

                if(call AMSend.send(AM_BROADCAST_ADDR, &pkg, sizeof(DistributeMsg)) == SUCCESS)
                {
                  busy = TRUE;

                }
                i++;
              }
            }
          }
          /*
             else,判断节点已经获得的prr-sinr点数时候已经>=  PRR_SINR_POINTS
             若是，则节点在此period睡眠
           */
          break;

        case PERIOD_END:
          if(has_choose_trans)
          {
            remainning_points--;
          }
          has_choose_trans = FALSE;
          remainning_points_of_neighbour = 0;
          //每隔20ms
          Timer1.start((TOS_NODE_ID-1)*20);
          //prr[sinr_in_period] = (float)received_packet[sinr_in_period] / MAX_PKG ; 
          break;

        case  END_ALL:
          //every node shoud transmit their prr[] to the sink
          end_all = TRUE;
          Timer1.start( (TOS_NODE_ID-1) * 20);
          break;

        case IN_PERIOD:
          if(!has_choose_trans)
          {
            rssi = getRssi(msg);
            sinr = computeSinr(rssi_of_neighbour[id-2], rssi);
            //此sinr无效 或者已经不需要再测sinr了
            if(sinr == -100)
            {
              break;
            }
            sinr_in_period = sinr;
            if(!prr_sinr[sinr])
            {
              received_packet[sinr] = 1;
              chosen_trans_id = id;
              has_choose_trans  = TRUE;
            }
          }
          else
          {
            if(id == chosen_trans_id)
            {
              received_packet[sinr_in_period]++;

            }
          }
          break;

        case COMMAND_REPORT_POINTS:
          if(dmpkt->data[NODE_ID_POSITION] == TOS_NODE_ID)
          {
            dmpkt->data[COMMAND_POSITION] = REPORT_POINTS;
            dmpkt->nodeid = TOS_NODE_ID;
            dmpkt->counter = 0;
            //需要将发送功率提高到最大确保sink能够接受到
            call CC2420Packet.setPower(&pkg,MAX_POWER);
            dmpkt->data[4] = call CC2420Packet.getPower(&pkg);
            dmpkt->data[0] = remainning_points;
            if( call AMSend(AM_BROADCAST_ADDR, &pkg, sizeof(DistributeMsg)) == SUCCESS)
            {
              busy = TRUE;
            }

          }

          break;

        case REPORT_POINTS:
          //发送此包的是接受者的邻居
          if(rssi_of_neighbour[id-2] != 255)
          {
            remainning_points_of_neighbour += dmpkt->data[0];
          }
          break;

        default:
          break;
      }
    }
    //when sink receives packets
    //the sink should reports the received packets to the computer
    else
    {

      switch(com)
      {
          case REPORT_POINTS:
            //data[0]被用来存放剩余点数
            remain_points_for_sink += (DistributeMsg*)(payload)->data[0]; 
            if(id == MAX_NODE_ID)
            {
                if(num_of_period < MAX_PERIOD && remain_points_for_sink == 0)
                {
                    sinkStartPeriod();
                }
                else  //整个过程结束
                {
                    DistributeMsg* dmpkt = (DistributeMsg*)(call Packet.getPayload(&pkg, sizeof(DistributeMsg)));
                    dmpkt->nodeid = TOS_NODE_ID;
                    dmpkt->data[COMMAND_POSITION] = END_ALL;
                    dmpkt->counter = 0;

                    reportToComputer(&pkg);

                    if( call AMSend(AM_BROADCAST_ADDR, &pkg, sizeof(DistributeMsg)) == SUCCESS)
                    {
                      busy = TRUE;
                    }
                }
            }
            reportToComputer(msg);
            break;

          case REPORT_PRR:
            reportToComputer(msg);
            break;

          default:
            break;

      }
    }
  }

  //若计算所得的sinr不在过渡区域，则返回-100
  uint16_t computeSinr(uint16_t trans, uint16_t all)
  {
    if (trans == 255)
    {
      return -100;
    }
    uint16_t res = trans / (all - trans);
    if(res >= MIN_SINR && res <= MAX_SINR)
    {
        return res;
    }
    else
    {
        return -100;
    }
  }

  uint16_t getRssi(message_t* msg)
  {
    rssi = call CC2420Packet.getRssi(msg);
    rssi = rssi & 0x00ff;
    rssi = getRealRssi(rssi);
    return rssi;
  }

  bool takePart(uint16_t remain)
  {
    period_times++;
      //如果是第一次的话，则以概率1/2充当发送者
      if(period_times == 1)
      {

      }
      //否则，看邻居平均剩余点数是否多余本机，是的话，充当接受者，否则，以概率1/2充当发送者
      else
      {
          if(remain > (remainning_points)/
          {
              return TRUE;
          }
          else
          {
              return FALSE;
          }
      }

  }
  //transform the measured rssi to the real rssi
  uint16_t getRealRssi(uint16_t rssi)
  {

  }

  void sinkStartPeriod()
  {
    DistributeMsg* dmpkt = (DistributeMsg*)(call Packet.getPayload(&pkg, sizeof(DistributeMsg)));
    dmpkt->nodeid = TOS_NODE_ID;
    dmpkt->data[COMMAND_POSITION] = PERIOD_BEGIN;
    dmpkt->counter = 0;

    //将sink发送的包同时也发送给电脑
    reportToComputer(&pkg);

    if( call AMSend(AM_BROADCAST_ADDR, &pkg, sizeof(DistributeMsg)) == SUCCESS)
    {
      busy = TRUE;
    }
    num_of_period++;
  }

  void reportToComputer(message_t* msg)
  {
    //先将sink接收到的包发送给电脑
    if(!UARTBusy)
    {
      if( call UARTSend.send(0xffff,msg, call RadioPacket.payloadLength(msg)) == SUCCESS)
      {
        UARTBusy = TRUE;
      }
    }
  }
}

