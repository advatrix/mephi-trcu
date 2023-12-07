/**
* helloworld.c: simple test application
*
* This application configures UART 16550 to baud rate 9600.
* PS7 UART (Zynq) is not initialized by this application, since
* bootrom/bsp configures it to baud rate 115200
*
* ------------------------------------------------
* | UART TYPE BAUD RATE |
* ------------------------------------------------
* uartns550 9600
* uartlite Configurable only in HW design
* ps7_uart 115200 (configured by bootrom/bsp)
*
*/
// код предоставляется на правах как есть – если у вас он не заработал, и вы не получили
// зачет, преподаватель тут не причем =))))
#include <stdio.h>
#include "xparameters.h"
#include "platform.h"
#include "xil_printf.h"
#include "xaxidma.h"
#include "xscugic.h"
#include "xil_exception.h"
#define DMA_DEV_ID XPAR_AXIDMA_0_DEVICE_ID
#define INTC_DEVICE_ID XPAR_SCUGIC_SINGLE_DEVICE_ID
#define FRAME_SIZE 2*480*641
#define FRAME_PARTS 40
#define FRAME_PART_SIZE FRAME_SIZE/FRAME_PARTS
#define INTC XScuGic
#define INTC_HANDLER XScuGic_InterruptHandler
#define TX_INTR_ID XPAR_FABRIC_AXI_DMA_0_MM2S_INTROUT_INTR
#define VGA_INTR_ID 62
#define FRAME_0_BASE (XPAR_PS7_DDR_0_S_AXI_BASEADDR + 0x00100000)
#define FRAME_1_BASE (XPAR_PS7_DDR_0_S_AXI_BASEADDR + 0x00110000)
XAxiDma AxiDma; /* Instance of the XAxiDma */
INTC Intc; /* Instance of the Interrupt Controller */
/* глобальные переменные, используемые в обработчике прерываний */
int frame_part = 0;
int new_frame_ready = 0;
u8 corent_frame = 1;
int SetupIntrSystem(INTC * IntcInstancePtr,XAxiDma * AxiDmaPtr, u16 TxIntrId, u16
RxIntrId);
void TxIntrHandler(void *Callback);
void Data_reqwestIntrHandler(void *Callback);
typedef struct Krug{
 u16 x,y,r2;
 u16 col;
} Krug;
int main()
{
 int Status;
 int Index;
 int x,y;
 u16* Frame_Base_Addr;
 u16 *frame0 = (u16*)FRAME_0_BASE,
 *frame1 = (u16*)FRAME_1_BASE;
 char key;
 Krug k = {640/2,480/2,1600,0xFF0};
 init_platform();
 xil_printf("Start\n\r");
 XAxiDma_Config *CfgPtr;
 CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
 if (!CfgPtr) {
 xil_printf("No config found for %d\r\n", DMA_DEV_ID);
 return XST_FAILURE;
 }
 Status = XAxiDma_CfgInitialize(&AxiDma, CfgPtr);
 if (Status != XST_SUCCESS) {
 xil_printf("Initialization failed %d\r\n", Status);
 return XST_FAILURE;
 }
 if(XAxiDma_HasSg(&AxiDma)){
 xil_printf("Device configured as SG mode \r\n");
 return XST_FAILURE;
 }
 XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
 /*Начальное заполнение кадра*/
 for(Index = 0; Index < FRAME_SIZE/2; Index++){
 frame0[Index] = frame1[Index] = 0x0;
 }
 frame0[0] = frame1[0] = 0x2000;
 Xil_DCacheFlushRange((UINTPTR)frame0, FRAME_SIZE);
 Xil_DCacheFlushRange((UINTPTR)frame1, FRAME_SIZE);
 Status = SetupIntrSystem(&Intc, &AxiDma, TX_INTR_ID, VGA_INTR_ID);

 if (Status != XST_SUCCESS) {
 xil_printf("Failed intr setup\r\n");
 return XST_FAILURE;
 }
 /* Disable all interrupts before setup */
 XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
 XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
 /* Enable all interrupts */
 XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
 XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
 /* Основной цикл */
 while(1){
 while(new_frame_ready);
 Frame_Base_Addr = !corent_frame ? frame1 : frame0 ;

 for (Index = 0; Index < 15; i++) {
	 // sprites filling
	 //"1" & "0000" & "1" & B"0000_0000_00"
	 Frame_Base_Addr[Index] = 0b1000010000000000;
 }

 for (int i = 0; i < 40; i++) {
	 for (int j = 0; i < 30; j++) {
		 // "1" & "0" & "001" & B"0000_0000_000";
		 Frame_Base_Addr[Index] = 0b10001000000000;
		 Index++;
	 }
 }


// for(Index = 0; Index < FRAME_SIZE/2; Index++)
// {
// x = Index%640 - k.x;
// y = Index/640 - k.y;
// if(x*x+y*y < k.r2)
// Frame_Base_Addr[Index] = k.col;
// else
// Frame_Base_Addr[Index] = 0x0000;
// }
// Frame_Base_Addr[0] = Frame_Base_Addr[0]|0x2000;
 Xil_DCacheFlushRange((UINTPTR)Frame_Base_Addr, FRAME_SIZE);
 new_frame_ready = 1;

 key = inbyte();
 switch(key){
 case 'w':
 k.y += 10;
 break;
 case 'a':
 k.x -= 10;
 break;
 case 'd':
 k.x += 10;
 break;
 case 's':
 k.y -= 10;
 break;
 }
 xil_printf("%c",key);
 }
 cleanup_platform();
 return 0;
}
int SetupIntrSystem(INTC * IntcInstancePtr,
 XAxiDma * AxiDmaPtr, u16 TxIntrId, u16 Data_reqwestIntrId)
{
 int Status;
 XScuGic_Config *IntcConfig;
 IntcConfig = XScuGic_LookupConfig(INTC_DEVICE_ID);
 if (NULL == IntcConfig) {
 return XST_FAILURE;
 }
 Status = XScuGic_CfgInitialize(IntcInstancePtr, IntcConfig,
 IntcConfig->CpuBaseAddress);
 if (Status != XST_SUCCESS) {
 return XST_FAILURE;
 }
 XScuGic_SetPriorityTriggerType(IntcInstancePtr, TxIntrId, 0xA0, 0x3);
 XScuGic_SetPriorityTriggerType(IntcInstancePtr, Data_reqwestIntrId, 0xA0, 0x0);
 Status = XScuGic_Connect(IntcInstancePtr, TxIntrId,
 (Xil_InterruptHandler)TxIntrHandler,
 AxiDmaPtr);
 if (Status != XST_SUCCESS) {
 return Status;
 }
 Status = XScuGic_Connect(IntcInstancePtr, Data_reqwestIntrId,
 (Xil_InterruptHandler)Data_reqwestIntrHandler,
 AxiDmaPtr);
 if (Status != XST_SUCCESS) {
 return Status;
 }
 XScuGic_Enable(IntcInstancePtr, TxIntrId);
 XScuGic_Enable(IntcInstancePtr, Data_reqwestIntrId);
 Xil_ExceptionInit();
 Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
 (Xil_ExceptionHandler)INTC_HANDLER,
 (void *)IntcInstancePtr);
 Xil_ExceptionEnable();
 return 0;
}
void TxIntrHandler(void *Callback)
{
 XScuGic_Enable(&Intc, VGA_INTR_ID);
 XAxiDma *AxiDmaInst = (XAxiDma *)Callback;
 u32 IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE);
 XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DMA_TO_DEVICE);
 if (frame_part == 0 && new_frame_ready == 1){
 corent_frame = !corent_frame;
 new_frame_ready = 0;
 }
}
void Data_reqwestIntrHandler(void *Callback)
{
 u8* Frame_Base_Addr = corent_frame ? (u8 *)FRAME_1_BASE : (u8 *)FRAME_0_BASE;
 XAxiDma_SimpleTransfer( &AxiDma,
 (UINTPTR) (Frame_Base_Addr + frame_part * FRAME_PART_SIZE),
 FRAME_PART_SIZE,
XAXIDMA_DMA_TO_DEVICE);
 XScuGic_Disable(&Intc, VGA_INTR_ID);
 frame_part = (frame_part + 1)%FRAME_PARTS;
}
