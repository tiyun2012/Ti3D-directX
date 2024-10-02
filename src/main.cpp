#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <d3dcompiler.h>
#include <DirectXMath.h>
#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx12.h"
#include "d3dx12.h"
#include <tchar.h>
#include <iostream>

// Link necessary libraries
#pragma comment(lib, "d3d12.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

// Forward declare the function
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

// Globals for DirectX 12
ID3D12Device* g_pd3dDevice = nullptr;
ID3D12DescriptorHeap* g_pd3dSrvDescHeap = nullptr;
ID3D12CommandQueue* g_pd3dCommandQueue = nullptr;
IDXGISwapChain3* g_pSwapChain = nullptr;
ID3D12CommandAllocator* g_commandAllocators[2]; // Double buffering
ID3D12GraphicsCommandList* g_pd3dCommandList = nullptr;
ID3D12Fence* g_pFence = nullptr;
UINT64 g_fenceLastSignaledValue = 0;
HANDLE g_hFenceEvent = nullptr;
UINT g_frameIndex = 0;
ID3D12Resource* g_mainRenderTargetResource[2];
D3D12_CPU_DESCRIPTOR_HANDLE g_mainRenderTargetDescriptor[2];
HWND hWnd = nullptr;
UINT g_rtvDescriptorSize;

// Window callback procedure
LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return true;

    switch (msg) {
    case WM_SIZE:
        if (g_pd3dDevice != nullptr && wParam != SIZE_MINIMIZED) {
            // Resize swap chain and resources if needed
        }
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProc(hWnd, msg, wParam, lParam);
}

// Create SRV Descriptor Heap for ImGui
bool CreateSrvDescriptorHeap() {
    D3D12_DESCRIPTOR_HEAP_DESC srvHeapDesc = {};
    srvHeapDesc.NumDescriptors = 1;
    srvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
    srvHeapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;

    HRESULT result = g_pd3dDevice->CreateDescriptorHeap(&srvHeapDesc, IID_PPV_ARGS(&g_pd3dSrvDescHeap));
    if (FAILED(result)) {
        OutputDebugStringA("Failed to create SRV Descriptor Heap for ImGui!");
        return false;
    }

    return true;
}

// Create Render Target Views (RTVs) for the swap chain
bool CreateRenderTargetViews() {
    D3D12_DESCRIPTOR_HEAP_DESC rtvHeapDesc = {};
    rtvHeapDesc.NumDescriptors = 2;
    rtvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    rtvHeapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
    HRESULT result = g_pd3dDevice->CreateDescriptorHeap(&rtvHeapDesc, IID_PPV_ARGS(&g_pd3dSrvDescHeap));
    if (FAILED(result)) {
        OutputDebugStringA("Failed to create RTV Descriptor Heap!");
        return false;
    }

    g_rtvDescriptorSize = g_pd3dDevice->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

    for (UINT i = 0; i < 2; i++) {
        result = g_pSwapChain->GetBuffer(i, IID_PPV_ARGS(&g_mainRenderTargetResource[i]));
        if (FAILED(result)) {
            OutputDebugStringA("Failed to get Swap Chain Buffer!");
            return false;
        }

        g_mainRenderTargetDescriptor[i] = g_pd3dSrvDescHeap->GetCPUDescriptorHandleForHeapStart();
        g_mainRenderTargetDescriptor[i].ptr += i * g_rtvDescriptorSize;
        g_pd3dDevice->CreateRenderTargetView(g_mainRenderTargetResource[i], nullptr, g_mainRenderTargetDescriptor[i]);
    }

    return true;
}

// Create Command Allocators
bool CreateCommandAllocators() {
    for (int i = 0; i < 2; i++) {
        HRESULT result = g_pd3dDevice->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&g_commandAllocators[i]));
        if (FAILED(result)) {
            OutputDebugStringA("Failed to create Command Allocator!");
            return false;
        }
    }
    return true;
}

// Create Command List
bool CreateCommandList() {
    HRESULT result = g_pd3dDevice->CreateCommandList(
        0,                                 // Node mask (0 for a single GPU)
        D3D12_COMMAND_LIST_TYPE_DIRECT,    // Command list type
        g_commandAllocators[0],            // Associated command allocator
        nullptr,                           // Initial pipeline state object (optional)
        IID_PPV_ARGS(&g_pd3dCommandList)   // Command list output
    );

    if (FAILED(result)) {
        OutputDebugStringA("Failed to create Command List!");
        return false;
    }

    // Initially close the command list since it is open by default when created
    g_pd3dCommandList->Close();
    return true;
}

// Create Swap Chain
bool CreateSwapChain(HWND hWnd) {
    IDXGIFactory4* dxgiFactory = nullptr;
    HRESULT result = CreateDXGIFactory1(IID_PPV_ARGS(&dxgiFactory));
    if (FAILED(result)) {
        OutputDebugStringA("Failed to create DXGI Factory!");
        return false;
    }

    DXGI_SWAP_CHAIN_DESC1 swapChainDesc = {};
    swapChainDesc.BufferCount = 2;
    swapChainDesc.Width = 1280;
    swapChainDesc.Height = 800;
    swapChainDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swapChainDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapChainDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    swapChainDesc.SampleDesc.Count = 1;

    IDXGISwapChain1* tempSwapChain = nullptr;
    result = dxgiFactory->CreateSwapChainForHwnd(
        g_pd3dCommandQueue,
        hWnd,
        &swapChainDesc,
        nullptr,
        nullptr,
        &tempSwapChain
    );

    if (FAILED(result)) {
        OutputDebugStringA("Failed to create Swap Chain!");
        dxgiFactory->Release();
        return false;
    }

    result = tempSwapChain->QueryInterface(IID_PPV_ARGS(&g_pSwapChain));
    tempSwapChain->Release();
    dxgiFactory->Release();

    if (FAILED(result)) {
        OutputDebugStringA("Failed to query IDXGISwapChain3!");
        return false;
    }

    g_frameIndex = g_pSwapChain->GetCurrentBackBufferIndex();
    return true;
}

// Update frame index after each frame
void UpdateFrameIndex() {
    g_frameIndex = g_pSwapChain->GetCurrentBackBufferIndex();
}

// Initialize Direct3D 12 Device and Swap Chain
bool InitD3D12(HWND hWnd) {
    HRESULT result;

    result = D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&g_pd3dDevice));
    if (FAILED(result)) {
        OutputDebugStringA("Failed to create D3D12 device!");
        return false;
    }

    D3D12_COMMAND_QUEUE_DESC queueDesc = {};
    queueDesc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;
    queueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    result = g_pd3dDevice->CreateCommandQueue(&queueDesc, IID_PPV_ARGS(&g_pd3dCommandQueue));
    if (FAILED(result)) {
        OutputDebugStringA("Failed to create Command Queue!");
        return false;
    }

    if (!CreateSwapChain(hWnd)) {
        return false;
    }

    if (!CreateRenderTargetViews()) {
        return false;
    }

    if (!CreateCommandAllocators()) {
        return false;
    }

    if (!CreateCommandList()) {
        return false;
    }

    if (!CreateSrvDescriptorHeap()) {
        return false;
    }

    return true;
}

void RenderUI() {
    const float clearColor[] = { 0.0f, 0.3f, 0.3f, 1.0f }; // Set a distinct color for debugging
    g_commandAllocators[g_frameIndex]->Reset();
    g_pd3dCommandList->Reset(g_commandAllocators[g_frameIndex], nullptr);

    // Transition the back buffer to render target
    D3D12_RESOURCE_BARRIER barrier = {};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = g_mainRenderTargetResource[g_frameIndex];
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    g_pd3dCommandList->ResourceBarrier(1, &barrier);

    g_pd3dCommandList->ClearRenderTargetView(g_mainRenderTargetDescriptor[g_frameIndex], clearColor, 0, nullptr);

    // Set descriptor heap for ImGui rendering
    ID3D12DescriptorHeap* descriptorHeaps[] = { g_pd3dSrvDescHeap };
    g_pd3dCommandList->SetDescriptorHeaps(1, descriptorHeaps);

    // ImGui rendering with extra checks
    OutputDebugStringA("Preparing ImGui frame...");
    ImGui_ImplDX12_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    ImGui::Begin("Hello Window");
    if (ImGui::Button("Press me!")) {
        OutputDebugStringA("Button Pressed!");
    }
    ImGui::End();

    ImGui::Render();
    OutputDebugStringA("ImGui frame rendered.");

    ImGui_ImplDX12_RenderDrawData(ImGui::GetDrawData(), g_pd3dCommandList);

    // Transition back to present state
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
    g_pd3dCommandList->ResourceBarrier(1, &barrier);

    g_pd3dCommandList->Close();
    ID3D12CommandList* commandLists[] = { g_pd3dCommandList };
    g_pd3dCommandQueue->ExecuteCommandLists(1, commandLists);

    g_pSwapChain->Present(1, 0);
    UpdateFrameIndex();
}

int APIENTRY WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_CLASSDC, WndProc, 0L, 0L, GetModuleHandle(NULL), NULL, NULL, NULL, NULL, _T("ImGui Example"), NULL };
    RegisterClassEx(&wc);

    hWnd = CreateWindow(wc.lpszClassName, _T("Dear ImGui Example"), WS_OVERLAPPEDWINDOW, 100, 100, 1280, 800, NULL, NULL, wc.hInstance, NULL);

    if (!InitD3D12(hWnd)) {
        return -1;
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    ImGui::StyleColorsDark();

    if (!ImGui_ImplWin32_Init(hWnd)) {
        OutputDebugStringA("Failed to initialize ImGui for Win32!");
        return -1;
    }

    if (!ImGui_ImplDX12_Init(g_pd3dDevice, 2, DXGI_FORMAT_R8G8B8A8_UNORM, g_pd3dSrvDescHeap,
        g_pd3dSrvDescHeap->GetCPUDescriptorHandleForHeapStart(),
        g_pd3dSrvDescHeap->GetGPUDescriptorHandleForHeapStart())) {
        OutputDebugStringA("Failed to initialize ImGui for DirectX 12!");
        return -1;
    }

    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);

    MSG msg = { 0 };
    while (msg.message != WM_QUIT) {
        if (PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            continue;
        }

        RenderUI();
    }

    ImGui_ImplDX12_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();

    return (int)msg.wParam;
}
